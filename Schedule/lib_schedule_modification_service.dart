// lib/services/schedule_modification_service.dart
// Samantha AI — Schedule Modification Engine (Flutter/Dart)
//
// Handles:
//   • Inserting bulk events from Excel import JSON
//   • Parsing chat commands into actions
//   • Applying modifications / deletions
//   • Conflict detection before every write

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../models/schedule_event.dart';

class ScheduleModificationService {
  static final ScheduleModificationService _i = ScheduleModificationService._();
  static ScheduleModificationService get instance => _i;
  ScheduleModificationService._();

  final _db = FirebaseFirestore.instance;

  // ── CONFIG — replace with real values ───────────────────────────────────
  static String get _uid => 'default_user'; // → FirebaseAuth.instance.currentUser!.uid
  static const String _backendUrl = 'https://your-samantha-backend.com';
  // ─────────────────────────────────────────────────────────────────────────

  CollectionReference get _col =>
      _db.collection('users').doc(_uid).collection('schedule');

  // ═══════════════════════════════════════════════════════════════════════════
  // BULK IMPORT  — Inserts schedule_firestore.json output into Firestore
  // ═══════════════════════════════════════════════════════════════════════════

  /// Pass the decoded JSON list from schedule_firestore.json
  Future<BulkImportResult> importFromJson(List<Map<String, dynamic>> events) async {
    int inserted = 0, skipped = 0;
    final conflicts = <String>[];

    // Process in batches of 500 (Firestore limit)
    final batches = <WriteBatch>[];
    var batch = _db.batch();
    int batchCount = 0;

    for (final ev in events) {
      // Convert ISO strings to Timestamps
      final start = DateTime.parse(ev['startTime'] as String);
      final end   = DateTime.parse(ev['endTime']   as String);

      // Conflict check
      final existing = await _getEventsForDate(start);
      final conflicting = existing.where((e) =>
          e.startTime.isBefore(end) && e.endTime.isAfter(start)).toList();

      if (conflicting.isNotEmpty) {
        conflicts.add('${ev['title']} conflicts with ${conflicting.first.title}');
        skipped++;
        continue;
      }

      final docRef = _col.doc();
      batch.set(docRef, {
        'title':        ev['title'],
        'description':  ev['description'],
        'startTime':    Timestamp.fromDate(start),
        'endTime':      Timestamp.fromDate(end),
        'priority':     ev['priority']     ?? 'medium',
        'category':     ev['category']     ?? 'general',
        'source':       ev['source']       ?? 'samantha',
        'tags':         ev['tags']         ?? [],
        'isRecurring':  ev['isRecurring']  ?? false,
        'recurringRule':ev['recurringRule'],
        'aiGenerated':  ev['aiGenerated']  ?? true,
        'aiReason':     ev['aiReason']     ?? 'Generated from weekly template',
        'isConfirmed':  ev['isConfirmed']  ?? true,
      });

      inserted++;
      batchCount++;

      if (batchCount == 499) {
        batches.add(batch);
        batch = _db.batch();
        batchCount = 0;
      }
    }

    if (batchCount > 0) batches.add(batch);
    for (final b in batches) await b.commit();

    return BulkImportResult(
      inserted: inserted, skipped: skipped, conflicts: conflicts);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // COMMAND PARSER  — Natural language → ScheduleAction
  // ═══════════════════════════════════════════════════════════════════════════

  /// Calls the FastAPI backend for NL parsing, falls back to local rules.
  Future<ScheduleAction> parseCommand(String userInput) async {
    try {
      final res = await http.post(
        Uri.parse('$_backendUrl/schedule/parse'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'input': userInput,
          'context_date': DateTime.now().toIso8601String(),
        }),
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        return ScheduleAction.fromMap(data);
      }
    } catch (_) {}

    // Local fallback
    return _parseLocally(userInput);
  }

  ScheduleAction _parseLocally(String input) {
    final t = input.toLowerCase();

    ActionIntent intent;
    if (t.contains('add') || t.contains('schedule') || t.contains('create')) {
      intent = ActionIntent.add;
    } else if (t.contains('move') || t.contains('reschedule') || t.contains('shift') || t.contains('change')) {
      intent = ActionIntent.modify;
    } else if (t.contains('cancel') || t.contains('delete') || t.contains('remove') || t.contains('skip')) {
      intent = ActionIntent.delete;
    } else {
      intent = ActionIntent.query;
    }

    return ScheduleAction(
      intent: intent,
      rawInput: input,
      title: _extractTitle(t),
      date: _extractDate(t),
      newStartTime: intent == ActionIntent.modify ? _extractTime(t) : null,
      startTime: intent == ActionIntent.add ? _extractTime(t) : null,
      durationMinutes: _extractDuration(t),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ACTION EXECUTOR
  // ═══════════════════════════════════════════════════════════════════════════

  Future<ActionResult> executeAction(ScheduleAction action) async {
    switch (action.intent) {
      case ActionIntent.add:
        return await _executeAdd(action);
      case ActionIntent.modify:
        return await _executeModify(action);
      case ActionIntent.delete:
        return await _executeDelete(action);
      case ActionIntent.query:
        return await _executeQuery(action);
      default:
        return ActionResult.failure('Could not understand that command. Try: "Add...", "Move...", or "Cancel..."');
    }
  }

  // ── ADD ─────────────────────────────────────────────────────────────────────

  Future<ActionResult> _executeAdd(ScheduleAction action) async {
    final anchor = _resolveDate(action.date);
    if (anchor == null) return ActionResult.failure('Could not determine date.');

    final timeStr = action.startTime ?? '09:00';
    final parts = timeStr.split(':');
    final h = int.parse(parts[0]), m = int.parse(parts[1]);
    final start = DateTime(anchor.year, anchor.month, anchor.day, h, m);
    final end = start.add(Duration(minutes: action.durationMinutes ?? 60));

    // Conflict check
    final existing = await _getEventsForDate(start);
    final conflicts = existing.where((e) =>
        e.isConfirmed &&
        e.startTime.isBefore(end) &&
        e.endTime.isAfter(start)).toList();

    if (conflicts.isNotEmpty) {
      final alt = _suggestAlternatives(start, end, existing);
      return ActionResult.conflict(
        'That slot conflicts with "${conflicts.first.title}". '
        'Try: ${alt.join(", ")}',
        alternatives: alt,
      );
    }

    await _col.add({
      'title': action.title ?? 'New Event',
      'description': null,
      'startTime': Timestamp.fromDate(start),
      'endTime': Timestamp.fromDate(end),
      'priority': 'medium',
      'category': _guessCategory(action.title ?? ''),
      'source': 'samantha',
      'tags': <String>[],
      'isRecurring': false,
      'recurringRule': null,
      'aiGenerated': true,
      'aiReason': 'User requested new activity',
      'isConfirmed': true,
    });

    await _writeConflictAlert(start, false);
    return ActionResult.success('Added "${action.title}" at ${timeStr}.');
  }

  // ── MODIFY ──────────────────────────────────────────────────────────────────

  Future<ActionResult> _executeModify(ScheduleAction action) async {
    final date = _resolveDate(action.date);
    if (date == null) return ActionResult.failure('Could not determine date.');

    final docs = await _findEventByTitle(action.title ?? '', date);
    if (docs.isEmpty) {
      return ActionResult.failure('Could not find "${action.title}" on that day.');
    }

    final target = docs.first;
    final newTimeStr = action.newStartTime ?? '09:00';
    final parts = newTimeStr.split(':');
    final h = int.parse(parts[0]), m = int.parse(parts[1]);

    final oldStart = target.startTime;
    final oldEnd = target.endTime;
    final duration = oldEnd.difference(oldStart);

    final newStart = DateTime(date.year, date.month, date.day, h, m);
    final newEnd = newStart.add(duration);

    // Conflict check excluding the event itself
    final existing = (await _getEventsForDate(newStart))
        .where((e) => e.id != target.id).toList();
    final conflicts = existing.where((e) =>
        e.isConfirmed &&
        e.startTime.isBefore(newEnd) &&
        e.endTime.isAfter(newStart)).toList();

    if (conflicts.isNotEmpty) {
      final alt = _suggestAlternatives(newStart, newEnd, existing);
      return ActionResult.conflict(
        'Moving to $newTimeStr conflicts with "${conflicts.first.title}". '
        'Try: ${alt.join(", ")}',
        alternatives: alt,
      );
    }

    // Update tags
    final tags = List<String>.from(target.tags);
    if (!tags.contains('modified_by_user')) tags.add('modified_by_user');

    await _col.doc(target.id).update({
      'startTime': Timestamp.fromDate(newStart),
      'endTime': Timestamp.fromDate(newEnd),
      'tags': tags,
      'aiReason': 'Modified based on user request',
    });

    return ActionResult.success(
        'Moved "${target.title}" to $newTimeStr (${_formatTime(newStart)}–${_formatTime(newEnd)}).');
  }

  // ── DELETE ──────────────────────────────────────────────────────────────────

  Future<ActionResult> _executeDelete(ScheduleAction action) async {
    final date = _resolveDate(action.date);
    if (date == null) return ActionResult.failure('Could not determine date.');

    final docs = await _findEventByTitle(action.title ?? '', date);
    if (docs.isEmpty) {
      return ActionResult.failure('Could not find "${action.title}" on that day.');
    }

    final target = docs.first;
    final tags = List<String>.from(target.tags);
    if (!tags.contains('cancelled')) tags.add('cancelled');

    await _col.doc(target.id).update({
      'isConfirmed': false,
      'tags': tags,
      'aiReason': 'Cancelled by user request',
    });

    return ActionResult.success('Cancelled "${target.title}" on ${_formatDate(date)}.');
  }

  // ── QUERY ───────────────────────────────────────────────────────────────────

  Future<ActionResult> _executeQuery(ScheduleAction action) async {
    final date = _resolveDate(action.date) ?? DateTime.now();
    final events = await _getEventsForDate(date);
    final active = events.where((e) => e.isConfirmed).toList();

    // Build conflict list
    final conflicts = <String>[];
    for (int i = 0; i < active.length; i++) {
      for (int j = i + 1; j < active.length; j++) {
        if (active[i].startTime.isBefore(active[j].endTime) &&
            active[i].endTime.isAfter(active[j].startTime)) {
          conflicts.add('"${active[i].title}" and "${active[j].title}"');
        }
      }
    }

    String msg;
    if (active.isEmpty) {
      msg = 'No events on ${_formatDate(date)}.';
    } else if (conflicts.isNotEmpty) {
      msg = '${active.length} events on ${_formatDate(date)}. '
            '⚠️ ${conflicts.length} conflict(s): ${conflicts.first}.';
    } else {
      msg = '${active.length} events on ${_formatDate(date)} — no conflicts.';
    }

    return ActionResult.success(msg, events: active);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // INTERNAL HELPERS
  // ═══════════════════════════════════════════════════════════════════════════

  Future<List<ScheduleEvent>> _getEventsForDate(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final snap = await _col
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('startTime', isLessThan: Timestamp.fromDate(end))
        .orderBy('startTime')
        .get();
    return snap.docs.map(ScheduleEvent.fromFirestore).toList();
  }

  Future<List<ScheduleEvent>> _findEventByTitle(String title, DateTime date) async {
    final events = await _getEventsForDate(date);
    final t = title.toLowerCase();
    return events.where((e) =>
        e.title.toLowerCase().contains(t) && e.isConfirmed).toList();
  }

  Future<void> _writeConflictAlert(DateTime date, bool hasConflicts,
      {int count = 0}) async {
    final dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    await _db
        .collection('users').doc(_uid)
        .collection('conflict_alerts').doc(dateKey)
        .set({
      'hasConflicts': hasConflicts,
      'count': count,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  List<String> _suggestAlternatives(DateTime start, DateTime end,
      List<ScheduleEvent> existing) {
    final duration = end.difference(start);
    final day = start.date;
    final suggestions = <String>[];
    var candidate = DateTime(day.year, day.month, day.day, 8, 0);

    while (candidate.hour < 21 && suggestions.length < 3) {
      final cEnd = candidate.add(duration);
      if (cEnd.hour > 22) break;
      final overlap = existing.any((e) =>
          e.isConfirmed &&
          e.startTime.isBefore(cEnd) &&
          e.endTime.isAfter(candidate));
      if (!overlap) suggestions.add(_formatTime(candidate));
      candidate = candidate.add(const Duration(minutes: 30));
    }
    return suggestions;
  }

  DateTime? _resolveDate(String? label) {
    if (label == null) return DateTime.now();
    final now = DateTime.now();
    switch (label.toLowerCase()) {
      case 'today':     return now;
      case 'tomorrow':  return now.add(const Duration(days: 1));
      case 'monday':    return _nextWeekday(DateTime.monday);
      case 'tuesday':   return _nextWeekday(DateTime.tuesday);
      case 'wednesday': return _nextWeekday(DateTime.wednesday);
      case 'thursday':  return _nextWeekday(DateTime.thursday);
      case 'friday':    return _nextWeekday(DateTime.friday);
      case 'saturday':  return _nextWeekday(DateTime.saturday);
      case 'sunday':    return _nextWeekday(DateTime.sunday);
      default:
        try { return DateTime.parse(label); } catch (_) { return now; }
    }
  }

  DateTime _nextWeekday(int weekday) {
    final now = DateTime.now();
    var days = weekday - now.weekday;
    if (days <= 0) days += 7;
    return now.add(Duration(days: days));
  }

  String? _extractTitle(String t) {
    const known = [
      'exercise', 'running', 'ukulele', 'pencil sketch', 'sketch',
      'traveler tree', 'sapna canvas', 'phokat ka gyan', 'corporate kurukshetra',
      'debate video', 'gita app', 'samantha', 'office', 'breakfast', 'dinner',
    ];
    for (final k in known) {
      if (t.contains(k)) return k.split(' ').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ');
    }
    return null;
  }

  String? _extractDate(String t) {
    for (final d in ['today', 'tomorrow', 'monday', 'tuesday', 'wednesday',
        'thursday', 'friday', 'saturday', 'sunday']) {
      if (t.contains(d)) return d;
    }
    return null;
  }

  String? _extractTime(String t) {
    final pm = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*pm');
    final am = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*am');
    final hr = RegExp(r'(\d{1,2}):(\d{2})');

    Match? m = pm.firstMatch(t);
    if (m != null) {
      int h = int.parse(m.group(1)!);
      int mi = int.tryParse(m.group(2) ?? '0') ?? 0;
      if (h != 12) h += 12;
      return '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}';
    }
    m = am.firstMatch(t);
    if (m != null) {
      int h = int.parse(m.group(1)!);
      int mi = int.tryParse(m.group(2) ?? '0') ?? 0;
      if (h == 12) h = 0;
      return '${h.toString().padLeft(2, '0')}:${mi.toString().padLeft(2, '0')}';
    }
    m = hr.firstMatch(t);
    if (m != null) return '${m.group(1)!.padLeft(2, '0')}:${m.group(2)}';

    if (t.contains('morning'))   return '07:00';
    if (t.contains('afternoon')) return '14:00';
    if (t.contains('evening'))   return '19:00';
    if (t.contains('night'))     return '21:00';
    return null;
  }

  int? _extractDuration(String t) {
    final m = RegExp(r'for\s+(\d+)\s*(hour|hr|h|min|minute)').firstMatch(t);
    if (m == null) return null;
    final v = int.parse(m.group(1)!);
    return m.group(2)!.startsWith('h') ? v * 60 : v;
  }

  String _guessCategory(String title) {
    final t = title.toLowerCase();
    if (t.contains('exercise') || t.contains('run')) return 'exercise';
    if (t.contains('meeting') || t.contains('call')) return 'meeting';
    if (t.contains('ukulele') || t.contains('sketch')) return 'personal';
    if (t.contains('office') || t.contains('work')) return 'work';
    return 'deepWork';
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  String _formatDate(DateTime dt) =>
      '${dt.day}/${dt.month}/${dt.year}';
}

extension on DateTime {
  DateTime get date => DateTime(year, month, day);
}


// ═══════════════════════════════════════════════════════════════════════════
// DATA CLASSES
// ═══════════════════════════════════════════════════════════════════════════

enum ActionIntent { add, modify, delete, query, unknown }

class ScheduleAction {
  final ActionIntent intent;
  final String rawInput;
  final String? title;
  final String? date;
  final String? startTime;
  final String? newStartTime;
  final int? durationMinutes;

  const ScheduleAction({
    required this.intent,
    required this.rawInput,
    this.title,
    this.date,
    this.startTime,
    this.newStartTime,
    this.durationMinutes,
  });

  factory ScheduleAction.fromMap(Map<String, dynamic> m) {
    final intentStr = m['intent'] ?? m['action'] ?? 'unknown';
    ActionIntent intent;
    switch (intentStr) {
      case 'add_event':    case 'create': intent = ActionIntent.add;    break;
      case 'modify_event': case 'reschedule': intent = ActionIntent.modify; break;
      case 'delete_event': case 'delete': intent = ActionIntent.delete; break;
      case 'query':        intent = ActionIntent.query;  break;
      default:             intent = ActionIntent.unknown;
    }

    final ev = m['event'] as Map<String, dynamic>?;
    return ScheduleAction(
      intent: intent,
      rawInput: m['raw_input'] ?? '',
      title: m['title'] ?? ev?['title'],
      date: m['date'] ?? ev?['date'],
      startTime: m['startTime'] ?? (ev != null
          ? '${ev['start_time'] ?? '09:00'}' : null),
      newStartTime: m['newStartTime'],
      durationMinutes: m['durationMinutes'],
    );
  }
}

class ActionResult {
  final bool success;
  final String message;
  final List<String> alternatives;
  final List<ScheduleEvent> events;
  final bool hasConflict;

  const ActionResult._({
    required this.success,
    required this.message,
    this.alternatives = const [],
    this.events = const [],
    this.hasConflict = false,
  });

  factory ActionResult.success(String msg, {List<ScheduleEvent> events = const []}) =>
      ActionResult._(success: true, message: msg, events: events);

  factory ActionResult.failure(String msg) =>
      ActionResult._(success: false, message: msg);

  factory ActionResult.conflict(String msg, {List<String> alternatives = const []}) =>
      ActionResult._(success: false, message: msg,
          alternatives: alternatives, hasConflict: true);
}

class BulkImportResult {
  final int inserted;
  final int skipped;
  final List<String> conflicts;
  BulkImportResult({required this.inserted, required this.skipped, required this.conflicts});
}

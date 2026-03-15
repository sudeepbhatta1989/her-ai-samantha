// lib/services/schedule_service.dart
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../models/schedule_event.dart';

class ScheduleService {
  static final ScheduleService _i = ScheduleService._();
  static ScheduleService get instance => _i;
  ScheduleService._();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── CONFIG: change these two values ────────────────────────────────────────
  static String get _userId => IdentityService.instance.uidSync;   // → Firebase Auth UID
  static const String _backendUrl = 'https://your-samantha-backend.com'; // → your server
  // ────────────────────────────────────────────────────────────────────────────

  CollectionReference get _col =>
      _db.collection('users').doc(_userId).collection('schedule');

  // ── STREAMS ──────────────────────────────────────────────────────────────

  Stream<List<ScheduleEvent>> watchDay(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return _col
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('startTime', isLessThan: Timestamp.fromDate(end))
        .orderBy('startTime')
        .snapshots()
        .map((s) => s.docs.map(ScheduleEvent.fromFirestore).toList());
  }

  Stream<List<ScheduleEvent>> watchWeek(DateTime weekStart) {
    final end = weekStart.add(const Duration(days: 7));
    return _col
        .where('startTime', isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
        .where('startTime', isLessThan: Timestamp.fromDate(end))
        .orderBy('startTime')
        .snapshots()
        .map((s) => s.docs.map(ScheduleEvent.fromFirestore).toList());
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<ScheduleEvent> createEvent(ScheduleEvent event) async {
    final ref = await _col.add(event.toFirestore());
    return ScheduleEvent.fromFirestore(await ref.get());
  }

  Future<void> updateEvent(ScheduleEvent event) async =>
      _col.doc(event.id).update(event.toFirestore());

  Future<void> deleteEvent(String id) async =>
      _col.doc(id).delete();

  Future<void> rescheduleEvent(String id, DateTime start, DateTime end) async =>
      _col.doc(id).update({
        'startTime': Timestamp.fromDate(start),
        'endTime': Timestamp.fromDate(end),
      });

  // ── CONFLICT DETECTION ───────────────────────────────────────────────────

  Future<List<ConflictInfo>> detectConflicts(DateTime date) async {
    final events = await _getEventsForDate(date);
    final conflicts = <ConflictInfo>[];

    for (int i = 0; i < events.length; i++) {
      for (int j = i + 1; j < events.length; j++) {
        final a = events[i], b = events[j];
        if (a.overlapsWith(b)) {
          final overlapStart = a.startTime.isAfter(b.startTime) ? a.startTime : b.startTime;
          final overlapEnd = a.endTime.isBefore(b.endTime) ? a.endTime : b.endTime;
          conflicts.add(ConflictInfo(
            a: a, b: b,
            overlap: overlapEnd.difference(overlapStart),
            suggestions: _buildSuggestions(a, b, events),
          ));
        }
      }
    }
    return conflicts;
  }

  List<RescheduleSuggestion> _buildSuggestions(
    ScheduleEvent a, ScheduleEvent b, List<ScheduleEvent> all,
  ) {
    // Move the lower-priority event; if equal, move the shorter one
    final toMove = a.priority.index <= b.priority.index ? a : b;
    final slots = _freeSlots(all, toMove.startTime, toMove.duration);
    return slots.take(3).map((slot) => RescheduleSuggestion(
      eventId: toMove.id,
      eventTitle: toMove.title,
      newStart: slot,
      newEnd: slot.add(toMove.duration),
      reason: _slotLabel(slot),
    )).toList();
  }

  List<DateTime> _freeSlots(List<ScheduleEvent> events, DateTime date, Duration needed) {
    final d = DateTime(date.year, date.month, date.day);
    final slots = <DateTime>[];
    for (int h = 8; h <= 19; h++) {
      for (int m = 0; m < 60; m += 30) {
        final candidate = DateTime(d.year, d.month, d.day, h, m);
        final candEnd = candidate.add(needed);
        if (candEnd.hour > 21) break;
        final isFree = events.every((e) =>
            !ScheduleEvent(id: '', title: '', startTime: candidate, endTime: candEnd)
                .overlapsWith(e));
        if (isFree) slots.add(candidate);
      }
    }
    return slots;
  }

  String _slotLabel(DateTime t) {
    if (t.hour < 10) return 'Early morning — peak focus window';
    if (t.hour < 12) return 'Mid-morning — high energy time';
    if (t.hour < 14) return 'Pre-lunch — still sharp';
    if (t.hour < 17) return 'Afternoon — steady work window';
    return 'Evening — wrap-up time';
  }

  // ── AI DAILY BRIEFING ────────────────────────────────────────────────────

  Future<DailyBriefing> getDailyBriefing(DateTime date) async {
    final events = await _getEventsForDate(date);
    final conflicts = await detectConflicts(date);

    try {
      final res = await http.post(
        Uri.parse('$_backendUrl/schedule/briefing'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'date': date.toIso8601String(),
          'events': events.map((e) => {
            'title': e.title,
            'start': e.startTime.toIso8601String(),
            'end': e.endTime.toIso8601String(),
            'category': e.category.name,
            'priority': e.priority.name,
            'source': e.source.name,
          }).toList(),
          'conflicts': conflicts.length,
        }),
      ).timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        final d = jsonDecode(res.body);
        return DailyBriefing(
          date: date,
          summary: d['summary'] ?? _localSummary(events),
          events: events,
          conflicts: conflicts,
          insights: List<String>.from(d['insights'] ?? []),
          energyAdvice: d['energy_advice'] ?? '',
          focusWindows: List<String>.from(d['focus_windows'] ?? []),
        );
      }
    } catch (_) {}

    return _localBriefing(date, events, conflicts);
  }

  DailyBriefing _localBriefing(DateTime date, List<ScheduleEvent> events, List<ConflictInfo> conflicts) {
    final insights = <String>[];
    if (conflicts.isNotEmpty) insights.add('⚠️ ${conflicts.length} conflict${conflicts.length > 1 ? 's' : ''} need attention');
    if (events.where((e) => e.category == EventCategory.meeting).length >= 3) {
      insights.add('Heavy meeting day — protect recovery time between calls');
    }
    final gcal = events.where((e) => e.source == EventSource.googleCalendar).length;
    final apple = events.where((e) => e.source == EventSource.appleCalendar).length;
    if (gcal > 0 || apple > 0) {
      insights.add('📅 Synced from ${gcal > 0 ? "Google Calendar" : ""}${gcal > 0 && apple > 0 ? " + " : ""}${apple > 0 ? "Apple Calendar" : ""}');
    }
    return DailyBriefing(
      date: date, summary: _localSummary(events),
      events: events, conflicts: conflicts,
      insights: insights,
      energyAdvice: events.isEmpty
          ? 'Clear day — use it for your most important work.'
          : 'Stay hydrated and take short breaks between tasks.',
      focusWindows: [],
    );
  }

  String _localSummary(List<ScheduleEvent> events) {
    if (events.isEmpty) return 'Clear day — great for deep work or planning ahead.';
    final n = events.length;
    final high = events.where((e) => e.priority == EventPriority.high || e.priority == EventPriority.critical).length;
    return '$n event${n > 1 ? 's' : ''} today${high > 0 ? ', $high high-priority' : ''}.';
  }

  // ── NATURAL LANGUAGE PARSE ───────────────────────────────────────────────

  Future<Map<String, dynamic>> parseNaturalLanguage(String text) async {
    try {
      final res = await http.post(
        Uri.parse('$_backendUrl/schedule/parse'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'input': text, 'context_date': DateTime.now().toIso8601String()}),
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) return jsonDecode(res.body);
    } catch (_) {}
    return {'action': 'unknown'};
  }

  // ── INTERNAL ──────────────────────────────────────────────────────────────

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
}

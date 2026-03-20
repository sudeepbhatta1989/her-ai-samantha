// lib/providers/schedule_provider.dart
import 'package:flutter/foundation.dart';
import '../models/schedule_event.dart';
import '../services/schedule_service.dart';
import '../services/calendar_sync_service.dart';

class ScheduleProvider extends ChangeNotifier {
  final _svc = ScheduleService.instance;
  final _sync = CalendarSyncService.instance;

  DateTime _selectedDate = DateTime.now();
  DailyBriefing? briefing;
  bool loadingBriefing = false;
  bool syncing = false;
  String? syncStatus;
  String? calendarPermissionStatus;

  DateTime get selectedDate => _selectedDate;

  void selectDate(DateTime d) {
    _selectedDate = d;
    loadBriefing();
    notifyListeners();
  }

  // ── BRIEFING ──────────────────────────────────────────────────────────────

  Future<void> loadBriefing() async {
    loadingBriefing = true;
    notifyListeners();
    try {
      briefing = await _svc.getDailyBriefing(_selectedDate);
    } catch (_) {}
    loadingBriefing = false;
    notifyListeners();
  }

  // ── CALENDAR SYNC ─────────────────────────────────────────────────────────

  Future<void> syncCalendars() async {
    syncing = true;
    syncStatus = 'Syncing calendars...';
    notifyListeners();

    final hasPerms = await _sync.hasPermissions();
    if (!hasPerms) {
      final granted = await _sync.requestPermissions();
      if (!granted) {
        syncStatus = 'Calendar access denied. Enable in Settings.';
        syncing = false;
        notifyListeners();
        return;
      }
    }

    // Get categorised calendars for status message
    final cats = await _sync.getCategorisedCalendars();
    final parts = <String>[];
    if (cats['google']!.isNotEmpty) parts.add('Google Calendar');
    if (cats['apple']!.isNotEmpty) parts.add('Apple Calendar');
    syncStatus = 'Syncing ${parts.join(' + ')}...';
    notifyListeners();

    final count = await _sync.syncUpcomingEvents(daysAhead: 14);
    await loadBriefing();

    syncing = false;
    syncStatus = count > 0
        ? '✅ Synced $count events from ${parts.join(' + ')}'
        : '✅ Calendars up to date';
    notifyListeners();

    // Clear status after 3s
    await Future.delayed(const Duration(seconds: 3));
    syncStatus = null;
    notifyListeners();
  }

  // ── CRUD ─────────────────────────────────────────────────────────────────

  Future<void> createEvent(ScheduleEvent event) async {
    await _svc.createEvent(event);
    await loadBriefing();
    notifyListeners();
  }

  Future<void> updateEvent(ScheduleEvent event) async {
    await _svc.updateEvent(event);
    await loadBriefing();
    notifyListeners();
  }

  Future<void> deleteEvent(String id) async {
    await _svc.deleteEvent(id);
    await loadBriefing();
    notifyListeners();
  }

  Future<void> acceptReschedule(RescheduleSuggestion s) async {
    await _svc.rescheduleEvent(s.eventId, s.newStart, s.newEnd);
    await loadBriefing();
    notifyListeners();
  }
}

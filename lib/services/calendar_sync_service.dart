// lib/services/calendar_sync_service.dart
// Syncs events from Google Calendar + Apple Calendar into Firestore
// Uses: device_calendar (reads native iOS/Android calendars)
// Add to pubspec.yaml: device_calendar: ^4.3.0

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart';
import '../models/schedule_event.dart';

class CalendarSyncService {
  static final CalendarSyncService _i = CalendarSyncService._();
  static CalendarSyncService get instance => _i;
  CalendarSyncService._();

  final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();
  static String get _userId => 'samantha_personal_user';
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference get _col =>
      _db.collection('users').doc(_userId).collection('schedule');

  // ── PERMISSIONS ────────────────────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    final result = await _plugin.requestPermissions();
    return result.isSuccess && (result.data ?? false);
  }

  Future<bool> hasPermissions() async {
    final result = await _plugin.hasPermissions();
    return result.isSuccess && (result.data ?? false);
  }

  // ── FETCH ALL DEVICE CALENDARS ─────────────────────────────────────────────

  Future<List<Calendar>> getAvailableCalendars() async {
    final result = await _plugin.retrieveCalendars();
    if (!result.isSuccess || result.data == null) return [];
    return result.data!;
  }

  // Returns which calendars are from Google vs Apple
  Future<Map<String, List<Calendar>>> getCategorisedCalendars() async {
    final all = await getAvailableCalendars();
    final google = <Calendar>[];
    final apple = <Calendar>[];
    final other = <Calendar>[];

    for (final cal in all) {
      final name = (cal.name ?? '').toLowerCase();
      final accountName = (cal.accountName ?? '').toLowerCase();
      if (accountName.contains('gmail') || accountName.contains('google')) {
        google.add(cal);
      } else if (Platform.isIOS && !accountName.contains('gmail')) {
        apple.add(cal); // On iOS non-Gmail = iCloud/Apple
      } else {
        other.add(cal);
      }
    }
    return {'google': google, 'apple': apple, 'other': other};
  }

  // ── SYNC EVENTS FROM DEVICE CALENDARS → FIRESTORE ─────────────────────────

  Future<int> syncUpcomingEvents({int daysAhead = 14}) async {
    if (!await hasPermissions()) {
      final granted = await requestPermissions();
      if (!granted) return 0;
    }

    final calendars = await getAvailableCalendars();
    final now = DateTime.now();
    final end = now.add(Duration(days: daysAhead));
    int count = 0;

    final batch = _db.batch();

    for (final cal in calendars) {
      final result = await _plugin.retrieveEvents(
        cal.id,
        RetrieveEventsParams(startDate: now, endDate: end),
      );
      if (!result.isSuccess || result.data == null) continue;

      for (final event in result.data!) {
        if (event.start == null || event.end == null) continue;
        if (event.title == null || event.title!.trim().isEmpty) continue;

        final source = _calendarSource(cal);
        final docId = _externalEventDocId(event.eventId ?? '', source);

        final samanthaEvent = ScheduleEvent(
          id: docId,
          title: event.title!,
          description: event.description,
          startTime: event.start!,
          endTime: event.end!,
          source: source,
          externalCalendarId: event.eventId,
          category: _guessCategory(event.title ?? ''),
          isRecurring: event.recurrenceRule != null,
        );

        batch.set(_col.doc(docId), samanthaEvent.toFirestore(),
            SetOptions(merge: true));
        count++;
      }
    }

    await batch.commit();
    debugPrint('[CalendarSync] Synced $count events from device calendars');
    return count;
  }

  // ── WRITE BACK: Create event on device calendar ────────────────────────────

  Future<String?> createExternalEvent({
    required ScheduleEvent event,
    required String calendarId,
  }) async {
    final e = Event(calendarId)
      ..title = event.title
      ..description = event.description
      ..start = TZDateTime.from(event.startTime, local)
      ..end = TZDateTime.from(event.endTime, local);

    final result = await _plugin.createOrUpdateEvent(e);
    if (result?.isSuccess == true) return result!.data;
    return null;
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  EventSource _calendarSource(Calendar cal) {
    final account = (cal.accountName ?? '').toLowerCase();
    if (account.contains('gmail') || account.contains('google')) {
      return EventSource.googleCalendar;
    }
    return EventSource.appleCalendar;
  }

  String _externalEventDocId(String eventId, EventSource source) {
    final prefix = source == EventSource.googleCalendar ? 'gcal' : 'apple';
    return '${prefix}_${eventId.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}';
  }

  EventCategory _guessCategory(String title) {
    final t = title.toLowerCase();
    if (t.contains('meeting') || t.contains('call') || t.contains('sync') || t.contains('standup')) {
      return EventCategory.meeting;
    }
    if (t.contains('gym') || t.contains('run') || t.contains('workout') || t.contains('yoga')) {
      return EventCategory.exercise;
    }
    if (t.contains('doctor') || t.contains('dentist') || t.contains('clinic') || t.contains('hospital')) {
      return EventCategory.health;
    }
    if (t.contains('lunch') || t.contains('dinner') || t.contains('coffee') || t.contains('party')) {
      return EventCategory.social;
    }
    if (t.contains('focus') || t.contains('deep work') || t.contains('writing') || t.contains('coding')) {
      return EventCategory.deepWork;
    }
    return EventCategory.work;
  }
}

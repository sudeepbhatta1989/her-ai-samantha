// lib/models/schedule_event.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum EventSource { samantha, googleCalendar, appleCalendar }
enum EventPriority { low, medium, high, critical }
enum EventCategory { work, meeting, health, personal, deepWork, exercise, social, general }

extension EventCategoryX on EventCategory {
  String get emoji {
    const map = {
      EventCategory.meeting: '🤝', EventCategory.work: '💼',
      EventCategory.health: '🏥', EventCategory.personal: '👤',
      EventCategory.deepWork: '🧠', EventCategory.exercise: '💪',
      EventCategory.social: '🎉', EventCategory.general: '📌',
    };
    return map[this] ?? '📌';
  }
  String get label {
    const map = {
      EventCategory.meeting: 'Meeting', EventCategory.work: 'Work',
      EventCategory.health: 'Health', EventCategory.personal: 'Personal',
      EventCategory.deepWork: 'Deep Work', EventCategory.exercise: 'Exercise',
      EventCategory.social: 'Social', EventCategory.general: 'General',
    };
    return map[this] ?? 'General';
  }
}

class ScheduleEvent {
  final String id;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime endTime;
  final EventPriority priority;
  final EventCategory category;
  final EventSource source;
  final String? externalCalendarId; // Google/Apple calendar event ID
  final bool isRecurring;
  final bool aiSuggested;
  final String? aiReason;

  ScheduleEvent({
    required this.id,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    this.priority = EventPriority.medium,
    this.category = EventCategory.general,
    this.source = EventSource.samantha,
    this.externalCalendarId,
    this.isRecurring = false,
    this.aiSuggested = false,
    this.aiReason,
  });

  Duration get duration => endTime.difference(startTime);

  bool overlapsWith(ScheduleEvent other) =>
      startTime.isBefore(other.endTime) && endTime.isAfter(other.startTime);

  factory ScheduleEvent.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ScheduleEvent(
      id: doc.id,
      title: d['title'] ?? '',
      description: d['description'],
      startTime: (d['startTime'] as Timestamp).toDate(),
      endTime: (d['endTime'] as Timestamp).toDate(),
      priority: EventPriority.values.firstWhere(
          (e) => e.name == (d['priority'] ?? 'medium'),
          orElse: () => EventPriority.medium),
      category: EventCategory.values.firstWhere(
          (e) => e.name == (d['category'] ?? 'general'),
          orElse: () => EventCategory.general),
      source: EventSource.values.firstWhere(
          (e) => e.name == (d['source'] ?? 'samantha'),
          orElse: () => EventSource.samantha),
      externalCalendarId: d['externalCalendarId'],
      isRecurring: d['isRecurring'] ?? false,
      aiSuggested: d['aiSuggested'] ?? false,
      aiReason: d['aiReason'],
    );
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'description': description,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(endTime),
        'priority': priority.name,
        'category': category.name,
        'source': source.name,
        'externalCalendarId': externalCalendarId,
        'isRecurring': isRecurring,
        'aiSuggested': aiSuggested,
        'aiReason': aiReason,
      };

  ScheduleEvent copyWith({
    String? title, String? description,
    DateTime? startTime, DateTime? endTime,
    EventPriority? priority, EventCategory? category,
  }) => ScheduleEvent(
    id: id, title: title ?? this.title,
    description: description ?? this.description,
    startTime: startTime ?? this.startTime,
    endTime: endTime ?? this.endTime,
    priority: priority ?? this.priority,
    category: category ?? this.category,
    source: source, externalCalendarId: externalCalendarId,
    isRecurring: isRecurring, aiSuggested: aiSuggested, aiReason: aiReason,
  );
}

class ConflictInfo {
  final ScheduleEvent a;
  final ScheduleEvent b;
  final Duration overlap;
  final List<RescheduleSuggestion> suggestions;
  ConflictInfo({required this.a, required this.b, required this.overlap, required this.suggestions});
}

class RescheduleSuggestion {
  final String eventId;
  final String eventTitle;
  final DateTime newStart;
  final DateTime newEnd;
  final String reason;
  RescheduleSuggestion({required this.eventId, required this.eventTitle,
      required this.newStart, required this.newEnd, required this.reason});
}

class DailyBriefing {
  final DateTime date;
  final String summary;
  final List<ScheduleEvent> events;
  final List<ConflictInfo> conflicts;
  final List<String> insights;
  final String energyAdvice;
  final List<String> focusWindows;
  DailyBriefing({required this.date, required this.summary, required this.events,
      required this.conflicts, required this.insights,
      required this.energyAdvice, required this.focusWindows});
}

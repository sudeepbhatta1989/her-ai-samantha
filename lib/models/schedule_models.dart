// lib/models/schedule_models.dart
// Samantha AI - Schedule Management Models

import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Event Model
// ─────────────────────────────────────────────────────────────────────────────
class SamanthaEvent {
  final String id;
  final String title;
  final String? description;
  final DateTime startTime;
  final DateTime endTime;
  final EventPriority priority;
  final EventCategory category;
  final List<String> tags;
  final bool isRecurring;
  final String? recurringRule; // 'daily', 'weekly', 'weekdays'
  final bool aiGenerated;
  final String? aiReason;
  final bool isConfirmed;

  SamanthaEvent({
    required this.id,
    required this.title,
    this.description,
    required this.startTime,
    required this.endTime,
    this.priority = EventPriority.medium,
    this.category = EventCategory.general,
    this.tags = const [],
    this.isRecurring = false,
    this.recurringRule,
    this.aiGenerated = false,
    this.aiReason,
    this.isConfirmed = true,
  });

  Duration get duration => endTime.difference(startTime);

  bool overlapsWith(SamanthaEvent other) {
    return startTime.isBefore(other.endTime) &&
        endTime.isAfter(other.startTime);
  }

  factory SamanthaEvent.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return SamanthaEvent(
      id: doc.id,
      title: d['title'] ?? '',
      description: d['description'],
      startTime: (d['startTime'] as Timestamp).toDate(),
      endTime: (d['endTime'] as Timestamp).toDate(),
      priority: EventPriority.values.firstWhere(
        (e) => e.name == (d['priority'] ?? 'medium'),
        orElse: () => EventPriority.medium,
      ),
      category: EventCategory.values.firstWhere(
        (e) => e.name == (d['category'] ?? 'general'),
        orElse: () => EventCategory.general,
      ),
      tags: List<String>.from(d['tags'] ?? []),
      isRecurring: d['isRecurring'] ?? false,
      recurringRule: d['recurringRule'],
      aiGenerated: d['aiGenerated'] ?? false,
      aiReason: d['aiReason'],
      isConfirmed: d['isConfirmed'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'title': title,
        'description': description,
        'startTime': Timestamp.fromDate(startTime),
        'endTime': Timestamp.fromDate(endTime),
        'priority': priority.name,
        'category': category.name,
        'tags': tags,
        'isRecurring': isRecurring,
        'recurringRule': recurringRule,
        'aiGenerated': aiGenerated,
        'aiReason': aiReason,
        'isConfirmed': isConfirmed,
      };

  SamanthaEvent copyWith({
    String? title,
    String? description,
    DateTime? startTime,
    DateTime? endTime,
    EventPriority? priority,
    EventCategory? category,
    bool? isConfirmed,
  }) {
    return SamanthaEvent(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      priority: priority ?? this.priority,
      category: category ?? this.category,
      tags: tags,
      isRecurring: isRecurring,
      recurringRule: recurringRule,
      aiGenerated: aiGenerated,
      aiReason: aiReason,
      isConfirmed: isConfirmed ?? this.isConfirmed,
    );
  }
}

enum EventPriority { low, medium, high, critical }

enum EventCategory {
  work,
  meeting,
  health,
  personal,
  deepWork,
  exercise,
  social,
  general,
}

extension EventCategoryDisplay on EventCategory {
  String get label {
    switch (this) {
      case EventCategory.work: return 'Work';
      case EventCategory.meeting: return 'Meeting';
      case EventCategory.health: return 'Health';
      case EventCategory.personal: return 'Personal';
      case EventCategory.deepWork: return 'Deep Work';
      case EventCategory.exercise: return 'Exercise';
      case EventCategory.social: return 'Social';
      case EventCategory.general: return 'General';
    }
  }

  String get emoji {
    switch (this) {
      case EventCategory.work: return '💼';
      case EventCategory.meeting: return '🤝';
      case EventCategory.health: return '🏥';
      case EventCategory.personal: return '👤';
      case EventCategory.deepWork: return '🧠';
      case EventCategory.exercise: return '💪';
      case EventCategory.social: return '🎉';
      case EventCategory.general: return '📌';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Schedule Conflict
// ─────────────────────────────────────────────────────────────────────────────
class ScheduleConflict {
  final SamanthaEvent event1;
  final SamanthaEvent event2;
  final Duration overlapDuration;
  final List<RescheduleSuggestion> suggestions;

  ScheduleConflict({
    required this.event1,
    required this.event2,
    required this.overlapDuration,
    required this.suggestions,
  });
}

class RescheduleSuggestion {
  final String eventId;
  final String eventTitle;
  final DateTime newStartTime;
  final DateTime newEndTime;
  final String reason;

  RescheduleSuggestion({
    required this.eventId,
    required this.eventTitle,
    required this.newStartTime,
    required this.newEndTime,
    required this.reason,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Daily Briefing
// ─────────────────────────────────────────────────────────────────────────────
class DailyBriefing {
  final DateTime date;
  final String aiSummary;
  final List<SamanthaEvent> events;
  final List<ScheduleConflict> conflicts;
  final List<String> insights;
  final List<String> focusBlocks;
  final String energyAdvice;

  DailyBriefing({
    required this.date,
    required this.aiSummary,
    required this.events,
    required this.conflicts,
    required this.insights,
    required this.focusBlocks,
    required this.energyAdvice,
  });
}

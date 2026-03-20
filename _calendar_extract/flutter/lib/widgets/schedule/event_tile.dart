// lib/widgets/schedule/event_tile.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/schedule_event.dart';

const kBg      = Color(0xFF0A0A1A);
const kSurface = Color(0xFF12122A);
const kCard    = Color(0xFF1A1A35);
const kAccent  = Color(0xFF7C5CFC);
const kAccentLt= Color(0xFF9B7FFF);
const kText    = Color(0xFFEEEEFF);
const kSubtext = Color(0xFF9090B0);
const kDanger  = Color(0xFFFF4B6E);
const kSuccess = Color(0xFF4BFF91);
const kGoogleRed  = Color(0xFFEA4335);
const kAppleGray  = Color(0xFF8E8E93);

Color priorityColor(EventPriority p) {
  switch (p) {
    case EventPriority.critical: return kDanger;
    case EventPriority.high:     return const Color(0xFFFFB74B);
    case EventPriority.medium:   return kAccent;
    case EventPriority.low:      return const Color(0xFF4B8BFF);
  }
}

Color categoryColor(EventCategory c) {
  switch (c) {
    case EventCategory.meeting:  return kAccent;
    case EventCategory.work:     return const Color(0xFF5CB8FF);
    case EventCategory.health:   return kSuccess;
    case EventCategory.exercise: return const Color(0xFFFFB74B);
    case EventCategory.deepWork: return const Color(0xFFFF6B9D);
    default:                     return kSubtext;
  }
}

Color sourceColor(EventSource s) {
  switch (s) {
    case EventSource.googleCalendar: return kGoogleRed;
    case EventSource.appleCalendar:  return kAppleGray;
    default:                         return kAccent;
  }
}

String sourceLabel(EventSource s) {
  switch (s) {
    case EventSource.googleCalendar: return 'Google';
    case EventSource.appleCalendar:  return 'Apple';
    default:                         return 'Samantha';
  }
}

class EventTile extends StatelessWidget {
  final ScheduleEvent event;
  final bool hasConflict;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const EventTile({super.key, required this.event, this.hasConflict = false,
      this.onDelete, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(
          color: hasConflict ? kDanger : priorityColor(event.priority), width: 4)),
        boxShadow: hasConflict ? [BoxShadow(color: kDanger.withOpacity(0.08), blurRadius: 8)] : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Time
          SizedBox(width: 46, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(DateFormat('HH:mm').format(event.startTime),
                style: TextStyle(color: kAccent, fontSize: 13, fontWeight: FontWeight.w700)),
            Text(DateFormat('HH:mm').format(event.endTime),
                style: const TextStyle(color: kSubtext, fontSize: 11)),
          ])),
          const SizedBox(width: 10),
          // Content
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(event.category.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 5),
              Expanded(child: Text(event.title,
                  style: const TextStyle(color: kText, fontSize: 14, fontWeight: FontWeight.w600))),
              if (hasConflict) const Icon(Icons.warning_amber_rounded, color: kDanger, size: 15),
            ]),
            if (event.description != null && event.description!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(event.description!, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kSubtext, fontSize: 12)),
            ],
            const SizedBox(height: 7),
            Row(children: [
              _chip(event.category.label, categoryColor(event.category)),
              const SizedBox(width: 5),
              _chip(_dur(event.duration), const Color(0xFF2A2A4A)),
              if (event.source != EventSource.samantha) ...[
                const SizedBox(width: 5),
                _chip(sourceLabel(event.source), sourceColor(event.source)),
              ],
              if (event.aiSuggested) ...[
                const SizedBox(width: 5),
                _chip('✨ AI', const Color(0xFF2D1B6B)),
              ],
              const Spacer(),
              GestureDetector(onTap: onEdit,
                  child: const Padding(padding: EdgeInsets.all(4),
                      child: Icon(Icons.edit_outlined, size: 15, color: kSubtext))),
              GestureDetector(onTap: onDelete,
                  child: const Padding(padding: EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline, size: 15, color: kDanger))),
            ]),
          ])),
        ]),
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
  );

  String _dur(Duration d) => d.inHours >= 1
      ? '${d.inHours}h${d.inMinutes.remainder(60) > 0 ? " ${d.inMinutes.remainder(60)}m" : ""}'
      : '${d.inMinutes}m';
}

// lib/widgets/event_card.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/schedule_models.dart';

class EventCard extends StatelessWidget {
  final SamanthaEvent event;
  final bool hasConflict;
  final Color accentColor;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;

  const EventCard({
    super.key,
    required this.event,
    required this.accentColor,
    this.hasConflict = false,
    this.onTap,
    this.onDelete,
    this.onEdit,
  });

  static const Color _card = Color(0xFF1A1A35);
  static const Color _textPrimary = Color(0xFFEEEEFF);
  static const Color _textSecondary = Color(0xFF9090B0);
  static const Color _danger = Color(0xFFFF4B6E);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border(
            left: BorderSide(
              color: hasConflict ? _danger : _priorityColor(event.priority),
              width: 4,
            ),
          ),
          boxShadow: hasConflict
              ? [BoxShadow(color: _danger.withOpacity(0.1), blurRadius: 8)]
              : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Time column
              SizedBox(
                width: 48,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('HH:mm').format(event.startTime),
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      DateFormat('HH:mm').format(event.endTime),
                      style: const TextStyle(color: _textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(event.category.emoji, style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            event.title,
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (hasConflict)
                          const Icon(Icons.warning_amber_rounded, color: _danger, size: 16),
                      ],
                    ),
                    if (event.description != null && event.description!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        event.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _textSecondary, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _chip(event.category.label, _categoryColor(event.category)),
                        const SizedBox(width: 6),
                        _chip(_durationLabel(event.duration), const Color(0xFF3A3A5C)),
                        if (event.aiGenerated) ...[
                          const SizedBox(width: 6),
                          _chip('✨ AI', const Color(0xFF2D1B6B)),
                        ],
                        const Spacer(),
                        // Quick action buttons
                        GestureDetector(
                          onTap: onEdit,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.edit_outlined, size: 16, color: _textSecondary),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          onTap: onDelete,
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(Icons.delete_outline, size: 16, color: _danger),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w500)),
    );
  }

  String _durationLabel(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}h${d.inMinutes.remainder(60) > 0 ? ' ${d.inMinutes.remainder(60)}m' : ''}';
    return '${d.inMinutes}m';
  }

  Color _priorityColor(EventPriority p) {
    switch (p) {
      case EventPriority.critical: return const Color(0xFFFF4B6E);
      case EventPriority.high: return const Color(0xFFFFB74B);
      case EventPriority.medium: return const Color(0xFF7C5CFC);
      case EventPriority.low: return const Color(0xFF4B8BFF);
    }
  }

  Color _categoryColor(EventCategory c) {
    switch (c) {
      case EventCategory.meeting: return const Color(0xFF7C5CFC);
      case EventCategory.work: return const Color(0xFF5CB8FF);
      case EventCategory.health: return const Color(0xFF4BFF91);
      case EventCategory.exercise: return const Color(0xFFFFB74B);
      case EventCategory.deepWork: return const Color(0xFFFF6B9D);
      default: return const Color(0xFF9090B0);
    }
  }
}

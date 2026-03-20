// lib/widgets/conflict_banner.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/schedule_models.dart';

class ConflictBanner extends StatefulWidget {
  final ScheduleConflict conflict;
  final Function(RescheduleSuggestion) onAcceptSuggestion;

  const ConflictBanner({
    super.key,
    required this.conflict,
    required this.onAcceptSuggestion,
  });

  @override
  State<ConflictBanner> createState() => _ConflictBannerState();
}

class _ConflictBannerState extends State<ConflictBanner> {
  bool _expanded = false;

  static const Color _danger = Color(0xFFFF4B6E);
  static const Color _card = Color(0xFF1A1A35);
  static const Color _textPrimary = Color(0xFFEEEEFF);
  static const Color _textSecondary = Color(0xFF9090B0);
  static const Color _accent = Color(0xFF7C5CFC);

  @override
  Widget build(BuildContext context) {
    final c = widget.conflict;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _danger.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          // Header
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: _danger, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Schedule Conflict',
                            style: TextStyle(color: _danger, fontSize: 13, fontWeight: FontWeight.w700)),
                        Text(
                          '"${c.event1.title}" and "${c.event2.title}" overlap by ${_durationLabel(c.overlapDuration)}',
                          style: const TextStyle(color: _textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: _textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // Suggestions
          if (_expanded) ...[
            const Divider(color: Color(0xFF2A2A4A), height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Samantha suggests:',
                      style: TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  ...c.suggestions.map((s) => _buildSuggestion(s)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSuggestion(RescheduleSuggestion s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _accent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Move "${s.eventTitle}"',
                  style: const TextStyle(color: _textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('HH:mm').format(s.newStartTime)} – ${DateFormat('HH:mm').format(s.newEndTime)}',
                  style: TextStyle(color: _accent, fontSize: 12),
                ),
                Text(s.reason, style: const TextStyle(color: _textSecondary, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => widget.onAcceptSuggestion(s),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _accent.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _accent.withOpacity(0.4)),
              ),
              child: const Text('Accept',
                  style: TextStyle(color: Color(0xFF9B7FFF), fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  String _durationLabel(Duration d) {
    if (d.inHours >= 1) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}min';
  }
}

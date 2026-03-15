// lib/widgets/briefing_card.dart
import 'package:flutter/material.dart';
import '../models/schedule_models.dart';

class BriefingCard extends StatelessWidget {
  final DailyBriefing briefing;
  final Color accentColor;

  const BriefingCard({super.key, required this.briefing, required this.accentColor});

  static const Color _card = Color(0xFF1A1A35);
  static const Color _textPrimary = Color(0xFFEEEEFF);
  static const Color _textSecondary = Color(0xFF9090B0);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF1E1540), const Color(0xFF12122A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accentColor.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [accentColor, const Color(0xFFAA80FF)],
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: const Text('✨', style: TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 10),
                const Text('Samantha\'s Briefing',
                    style: TextStyle(color: _textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${briefing.events.length} events',
                    style: TextStyle(color: accentColor, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // AI Summary
            Text(briefing.aiSummary,
                style: const TextStyle(color: _textPrimary, fontSize: 14, height: 1.5)),

            // Insights
            if (briefing.insights.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Divider(color: Color(0xFF2A2A4A), height: 1),
              const SizedBox(height: 10),
              ...briefing.insights.map((insight) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(insight, style: const TextStyle(color: _textSecondary, fontSize: 13)),
                      ],
                    ),
                  )),
            ],

            // Energy advice
            if (briefing.energyAdvice.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1628),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Text('💡', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(briefing.energyAdvice,
                          style: const TextStyle(color: _textSecondary, fontSize: 12, height: 1.4)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

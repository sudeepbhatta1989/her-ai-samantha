import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const String LAMBDA_URL =
    'https://aybg83gr69.execute-api.ap-south-1.amazonaws.com/prod/chat';
const String USER_ID = 'user1';

class GoalsScreen extends StatefulWidget {
  const GoalsScreen({super.key});

  @override
  State<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends State<GoalsScreen> {
  Map<String, dynamic>? _profile;
  bool _loading = true;
  bool _saving = false;

  List<Map<String, dynamic>> _goals = [
    {'icon': '🎬', 'key': 'phokat_ka_gyan', 'title': 'Phokat ka Gyan', 'subtitle': 'YouTube Monetisation', 'progress': 0.15, 'target': '1000 subs + 4000 watch hours', 'color': 0xFFF59E0B, 'deadline': 'Dec 2026'},
    {'icon': '🌍', 'key': 'traveler_tree', 'title': 'Traveler Tree MVP', 'subtitle': 'App Launch', 'progress': 0.10, 'target': 'Play Store launch', 'color': 0xFF5FB8A0, 'deadline': 'Dec 2026'},
    {'icon': '📿', 'key': 'gita_app', 'title': 'Gita Learning App', 'subtitle': 'v1 Live', 'progress': 0.05, 'target': 'Flutter app on Play Store', 'color': 0xFFC9A96E, 'deadline': 'Dec 2026'},
    {'icon': '✏️', 'key': 'sketch', 'title': 'Pencil Sketching', 'subtitle': 'Semi-professional level', 'progress': 0.08, 'target': '30-60 min daily practice', 'color': 0xFF7C6FCD, 'deadline': 'Dec 2026'},
    {'icon': '🎵', 'key': 'ukulele', 'title': 'Ukulele', 'subtitle': '5 songs mastered', 'progress': 0.10, 'target': '30 min daily practice', 'color': 0xFF7DB8E0, 'deadline': 'Dec 2026'},
    {'icon': '🎨', 'key': 'sapna_canvas', 'title': 'Sapna Canvas', 'subtitle': 'Social media presence', 'progress': 0.05, 'target': 'Established Instagram brand', 'color': 0xFFE879A0, 'deadline': 'Mid 2026'},
    {'icon': '🏃', 'key': 'exercise', 'title': 'Daily Exercise', 'subtitle': '30 min every day', 'progress': 0.60, 'target': '365 day streak', 'color': 0xFFE07070, 'deadline': 'Ongoing'},
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loading = true);
    try {
      final response = await http.post(
        Uri.parse(LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': USER_ID, 'action': 'get_profile'}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      final profile = data['profile'] as Map<String, dynamic>?;
      if (profile != null) {
        setState(() {
          _profile = profile;
          final fg = profile['goals'] as Map<String, dynamic>?;
          if (fg != null) {
            for (final goal in _goals) {
              final key = goal['key'] as String;
              if (fg.containsKey(key)) {
                final g = fg[key] as Map<String, dynamic>;
                goal['progress'] = (g['progress'] ?? goal['progress']).toDouble();
                goal['target'] = g['target'] ?? goal['target'];
                goal['deadline'] = g['deadline'] ?? goal['deadline'];
              }
            }
          }
        });
      }
    } catch (e) {
      print('Load error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showEditDialog(Map<String, dynamic> goal) {
    final progressCtrl = TextEditingController(
        text: ((goal['progress'] as double) * 100).toInt().toString());
    final targetCtrl = TextEditingController(text: goal['target'] as String);
    final deadlineCtrl = TextEditingController(text: goal['deadline'] as String);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A24),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(goal['icon'] as String, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Text(goal['title'] as String,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            const Text('Or tell Samantha in chat — "Update my sketch goal to 20%"',
                style: TextStyle(fontSize: 11, color: Color(0xFF7A7590))),
            const SizedBox(height: 20),
            _field('Progress (%)', progressCtrl, isNumber: true),
            const SizedBox(height: 12),
            _field('Target / Milestone', targetCtrl),
            const SizedBox(height: 12),
            _field('Deadline', deadlineCtrl),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _saveGoal(goal,
                      progress: (int.tryParse(progressCtrl.text) ?? 0) / 100,
                      target: targetCtrl.text,
                      deadline: deadlineCtrl.text);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {bool isNumber = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF7A7590))),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF0C0C10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF2A2A3A))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF2A2A3A))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF7C3AED))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
      ],
    );
  }

  Future<void> _saveGoal(Map<String, dynamic> goal,
      {required double progress, required String target, required String deadline}) async {
    setState(() => _saving = true);
    try {
      final msg =
          'Please update my ${goal['title']} goal: progress is now ${(progress * 100).toInt()}%, target is "$target", deadline is "$deadline"';
      await http.post(Uri.parse(LAMBDA_URL),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'userId': USER_ID, 'message': msg}))
          .timeout(const Duration(seconds: 15));
      setState(() {
        goal['progress'] = progress;
        goal['target'] = target;
        goal['deadline'] = deadline;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✓ Samantha updated your goal!'),
          backgroundColor: Color(0xFF7C3AED),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      print('Save error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v3 = _profile?['vision_3yr'] ?? 'Own company. Leave corporate job. Creative independence.';
    final v1 = _profile?['vision_1yr'] ?? 'Phokat ka Gyan monetised + Traveler Tree MVP launched';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131A),
        title: const Text('Goals & Domains',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          _saving
              ? const Padding(padding: EdgeInsets.all(16),
                  child: SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7C3AED))))
              : IconButton(
                  icon: const Icon(Icons.refresh, color: Color(0xFF00D4FF)),
                  onPressed: _loadProfile),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF2A2A3A)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF)))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Tip
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.2)),
                  ),
                  child: const Row(children: [
                    Text('✦', style: TextStyle(color: Color(0xFF7C3AED))),
                    SizedBox(width: 10),
                    Expanded(child: Text(
                      'Tap any goal to update. Or tell Samantha in chat — she\'ll remember.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF7A7590), height: 1.5),
                    )),
                  ]),
                ),

                // Vision banner
                Container(
                  padding: const EdgeInsets.all(18),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      const Color(0xFF7C3AED).withOpacity(0.15),
                      const Color(0xFF00D4FF).withOpacity(0.05),
                    ]),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('3 YEAR VISION',
                          style: TextStyle(fontSize: 10, color: Color(0xFF7C3AED), letterSpacing: 0.15)),
                      const SizedBox(height: 6),
                      Text(v3, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
                      const SizedBox(height: 8),
                      const Divider(color: Color(0xFF2A2A3A)),
                      const SizedBox(height: 8),
                      const Text('1 YEAR GOAL',
                          style: TextStyle(fontSize: 10, color: Color(0xFF00D4FF), letterSpacing: 0.15)),
                      const SizedBox(height: 6),
                      Text(v1, style: const TextStyle(fontSize: 13, color: Color(0xFF7A7590), height: 1.5)),
                    ],
                  ),
                ),

                const Text('ACTIVE GOALS — 2026',
                    style: TextStyle(fontSize: 11, color: Color(0xFF00D4FF), letterSpacing: 0.15)),
                const SizedBox(height: 12),
                ..._goals.map((g) => _goalCard(g)),
              ],
            ),
    );
  }

  Widget _goalCard(Map<String, dynamic> goal) {
    final color = Color(goal['color'] as int);
    final progress = (goal['progress'] as num).toDouble();
    return GestureDetector(
      onTap: () => _showEditDialog(goal),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF16161F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2A2A3A)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(goal['icon'] as String, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(goal['title'] as String,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text(goal['subtitle'] as String,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF7A7590))),
                ],
              )),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Text(goal['deadline'] as String,
                    style: TextStyle(fontSize: 9, color: color)),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF7A7590)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: const Color(0xFF2A2A3A),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              )),
              const SizedBox(width: 10),
              Text('${(progress * 100).toInt()}%',
                  style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 6),
            Text(goal['target'] as String,
                style: const TextStyle(fontSize: 11, color: Color(0xFF7A7590))),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

const String LAMBDA_URL = 'https://aybg83gr69.execute-api.ap-south-1.amazonaws.com/prod/chat';
const String USER_ID = 'user1';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _morningBriefing;
  Map<String, dynamic>? _todayPlan;
  Map<String, dynamic> _streaks = {};
  bool _loadingBriefing = true;
  Map<String, dynamic> _weeklyInsights = {};

  final domains = [
    {'icon': '🎬', 'title': 'Phokat ka Gyan', 'task': 'Daily short at 8:30am', 'color': 0xFFF59E0B},
    {'icon': '🌍', 'title': 'Traveler Tree', 'task': 'App MVP development', 'color': 0xFF5FB8A0},
    {'icon': '📿', 'title': 'Gita App', 'task': 'Flutter development', 'color': 0xFFC9A96E},
    {'icon': '✏️', 'title': 'Pencil Sketch', 'task': '30–60 min practice', 'color': 0xFF7C6FCD},
    {'icon': '🎵', 'title': 'Ukulele', 'task': '30 min practice', 'color': 0xFF7DB8E0},
    {'icon': '🏃', 'title': 'Exercise', 'task': '30 min workout', 'color': 0xFFE07070},
  ];

  @override
  void initState() {
    super.initState();
    _loadMorningData();
  }

  Future<void> _loadMorningData() async {
    try {
      final todayStr = DateTime.now().toIso8601String().substring(0, 10);

      // ── Step 1: Try the pre-cached briefing first (Phase E — instant load) ──
      final cachedResponse = await http.post(
        Uri.parse(LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': USER_ID, 'action': 'get_cached_briefing', 'date': todayStr}),
      ).timeout(const Duration(seconds: 8));

      final cachedData = jsonDecode(cachedResponse.body);
      final cached = cachedData['briefing'];
      final cacheHit = cached != null && cached['date'] == todayStr;

      if (cacheHit && mounted) {
        // Instant display from cache — no wait
        setState(() {
          _morningBriefing = cached['full_briefing'] ?? cached['greeting'] ?? '';
          _todayPlan = {'top_priority': cached['top_priority'] ?? '', 'slots': cached['schedule_slots'] ?? []};
          _weeklyInsights = _buildInsightsFromCache(cached);
          _loadingBriefing = false;
        });
        // Load streaks in background
        _loadStreaksBackground();
        return;
      }

      // ── Step 2: Cache miss — fall back to live generation ──
      final response = await http.post(
        Uri.parse(LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': USER_ID, 'action': 'morning_briefing'}),
      ).timeout(const Duration(seconds: 20));

      final data = jsonDecode(response.body);

      // Get streaks in parallel (already fired above if cache hit)
      final streakResponse = await http.post(
        Uri.parse(LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': USER_ID, 'action': 'get_streaks'}),
      ).timeout(const Duration(seconds: 10));

      final streaks = Map<String, dynamic>.from(
        (jsonDecode(streakResponse.body))['streaks'] ?? {}
      );

      if (mounted) {
        setState(() {
          _morningBriefing = data['briefing'];
          _todayPlan = data['plan'];
          _streaks = streaks;
          _weeklyInsights = _computeWeeklyInsights(streaks);
          _loadingBriefing = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingBriefing = false);
    }
  }

  Future<void> _loadStreaksBackground() async {
    try {
      final res = await http.post(
        Uri.parse(LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': USER_ID, 'action': 'get_streaks'}),
      ).timeout(const Duration(seconds: 10));
      final streaks = Map<String, dynamic>.from((jsonDecode(res.body))['streaks'] ?? {});
      if (mounted) setState(() {
        _streaks = streaks;
        _weeklyInsights = _computeWeeklyInsights(streaks);
      });
    } catch (_) {}
  }

  Map<String, dynamic> _buildInsightsFromCache(Map<String, dynamic> cached) {
    final streaks = Map<String, dynamic>.from(cached['habit_streaks'] ?? {});
    int habitsToday = 0;
    int totalStreak = 0;
    String topHabit = '';
    int topStreak = 0;
    for (final entry in streaks.entries) {
      final s = (entry.value as num?)?.toInt() ?? 0;
      totalStreak += s;
      if (s > 0) habitsToday++;
      if (s > topStreak) { topStreak = s; topHabit = entry.key; }
    }
    return {
      'habitsCompletedToday': habitsToday,
      'totalStreak': totalStreak,
      'topHabit': topHabit,
      'topStreak': topStreak,
      'weeklyFocus': cached['top_priority'] ?? 'Stay consistent',
    };
  }

  /// Compute weekly insights from a streaks map — reusable after any update
  Map<String, dynamic> _computeWeeklyInsights(Map<String, dynamic> streaks) {
    int habitsCompletedToday = 0;
    int totalStreak = 0;
    String topHabit = '';
    int topStreak = 0;
    final today = DateTime.now().toIso8601String().split('T')[0];
    streaks.forEach((k, v) {
      if (v is Map) {
        final s = (v['current_streak'] ?? 0) as int;
        totalStreak += s;
        if (v['last_done'] == today) habitsCompletedToday++;
        if (s > topStreak) { topStreak = s; topHabit = k as String; }
      }
    });
    return {
      'habitsToday': habitsCompletedToday,
      'totalStreak': totalStreak,
      'topHabit': topHabit,
      'topStreak': topStreak,
    };
  }

  Future<void> _markHabitDone(String habit) async {
    try {
      final response = await http.post(
        Uri.parse(LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': USER_ID,
          'action': 'mark_habit',
          'habit': habit,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      final body = data;
      final streakData = body['streak_data'] as Map<String, dynamic>? ?? {};

      // Update streaks map and recompute weekly insights immediately
      final updatedStreaks = Map<String, dynamic>.from(_streaks);
      updatedStreaks[habit] = streakData;

      setState(() {
        _streaks = updatedStreaks;
        _weeklyInsights = _computeWeeklyInsights(updatedStreaks);
      });

      final streak = streakData['current_streak'] ?? 1;
      final habitLabels = {
        'daily_short': 'Daily Short',
        'sketch': 'Pencil Sketch',
        'ukulele': 'Ukulele',
        'exercise': 'Exercise',
      };
      final label = habitLabels[habit] ?? habit;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$label done! 🔥 $streak day streak'),
            backgroundColor: const Color(0xFF00D4FF),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Habit error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final hour = now.hour;
    String greeting;
    if (hour < 12) {
      greeting = 'Good Morning';
    } else if (hour < 17) {
      greeting = 'Good Afternoon';
    } else {
      greeting = 'Good Evening';
    }

    final topPriority = _todayPlan?['top_priority'] ?? 'Phokat ka Gyan monetisation is the key to everything';

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadMorningData,
        color: const Color(0xFF00D4FF),
        child: CustomScrollView(
          slivers: [
            // Header
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              backgroundColor: const Color(0xFF13131A),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF13131A), Color(0xFF0C0C10)],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '$greeting, Sudeep',
                            style: TextStyle(fontFamily: 'Sora', 
                              fontSize: 26,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('EEEE, MMMM d').format(now),
                            style: const TextStyle(color: Color(0xFF7A7590), fontSize: 14),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF00D4FF).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.3)),
                            ),
                            child: const Text(
                              '✦ Samantha is with you',
                              style: TextStyle(color: Color(0xFF00D4FF), fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Morning briefing from Samantha
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('SAMANTHA SAYS',
                        style: TextStyle(fontSize: 11, color: Color(0xFF7C3AED), letterSpacing: 0.15)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A24),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3)),
                      ),
                      child: _loadingBriefing
                          ? const Row(
                              children: [
                                SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF7C3AED),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text('Samantha is preparing your briefing...',
                                    style: TextStyle(color: Color(0xFF7A7590), fontSize: 13)),
                              ],
                            )
                          : Text(
                              _morningBriefing ?? 'Good to see you! Ready to make today count?',
                              style: const TextStyle(fontSize: 13, height: 1.6, color: Color(0xFFE0E0F0)),
                            ),
                    ),
                  ],
                ),
              ),
            ),

            // Today's top priority
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("TODAY'S FOCUS",
                        style: TextStyle(fontSize: 11, color: Color(0xFF00D4FF), letterSpacing: 0.15)),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1A1A24), Color(0xFF16161F)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFC9A96E).withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            topPriority,
                            style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFFC9A96E),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Every video published is a step toward leaving the corporate job.',
                            style: TextStyle(fontSize: 13, color: Color(0xFF7A7590), height: 1.5),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _buildStat('📹', 'Daily Short', 'Due 8:30am'),
                              const SizedBox(width: 12),
                              _buildStat('⏱️', 'Office Hours', 'Until 7:15pm'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Habit tracker
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("TODAY'S HABITS",
                        style: TextStyle(fontSize: 11, color: Color(0xFF00D4FF), letterSpacing: 0.15)),
                    const SizedBox(height: 10),
                    _buildHabitRow('daily_short', '📹', 'Daily Short', '8:30am'),
                    const SizedBox(height: 8),
                    _buildHabitRow('sketch', '✏️', 'Pencil Sketch', '30-60 min'),
                    const SizedBox(height: 8),
                    _buildHabitRow('ukulele', '🎵', 'Ukulele', '30 min'),
                    const SizedBox(height: 8),
                    _buildHabitRow('exercise', '🏃', 'Exercise', '30 min'),
                  ],
                ),
              ),
            ),

            // Weekly insights card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _buildWeeklyInsights(),
              ),
            ),

            // Domain cards
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: const Text('YOUR DOMAINS',
                    style: TextStyle(fontSize: 11, color: Color(0xFF00D4FF), letterSpacing: 0.15)),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.5,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final domain = domains[i];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF16161F),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF2A2A3A)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(domain['icon'] as String, style: const TextStyle(fontSize: 18)),
                              const Spacer(),
                              Container(
                                width: 6, height: 6,
                                decoration: BoxDecoration(
                                  color: Color(domain['color'] as int),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          Text(domain['title'] as String,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(domain['task'] as String,
                              style: const TextStyle(fontSize: 10, color: Color(0xFF7A7590)),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    );
                  },
                  childCount: domains.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _weekExpanded = false;

  Widget _buildWeeklyInsights() {
    final habitsToday = _weeklyInsights['habitsToday'] ?? 0;
    final topStreak = _weeklyInsights['topStreak'] ?? 0;
    final today = DateTime.now().toIso8601String().split('T')[0];

    // Per-habit breakdown from streaks
    final habitDefs = [
      {'key': 'daily_short', 'icon': '📹', 'label': 'Daily Short'},
      {'key': 'sketch',      'icon': '✏️',  'label': 'Sketch'},
      {'key': 'ukulele',     'icon': '🎵',  'label': 'Ukulele'},
      {'key': 'exercise',    'icon': '🏃',  'label': 'Exercise'},
    ];

    String summaryMsg;
    if (habitsToday == 4) summaryMsg = '🔥 Perfect day — all 4 done!';
    else if (habitsToday == 3) summaryMsg = '✅ 3/4 done — one more!';
    else if (habitsToday == 2) summaryMsg = '⚡ 2/4 done — keep going.';
    else if (habitsToday == 1) summaryMsg = '📌 1/4 — start building momentum.';
    else summaryMsg = '📌 No habits yet today — start now.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('THIS WEEK',
            style: TextStyle(fontSize: 11, color: Color(0xFF00D4FF), letterSpacing: 0.15)),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: () => setState(() => _weekExpanded = !_weekExpanded),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF1A1020), Color(0xFF120C1E)],
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary row — always visible
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$habitsToday/4 habits today',
                        style: const TextStyle(fontSize: 11, color: Color(0xFFAA88FF)),
                      ),
                    ),
                    const Spacer(),
                    if (topStreak > 0)
                      Text('🔥 $topStreak day streak',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFF59E0B))),
                    const SizedBox(width: 8),
                    Icon(
                      _weekExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                      size: 16, color: const Color(0xFF7A7590),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(summaryMsg,
                    style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.4)),

                // Expanded breakdown — per habit streaks
                if (_weekExpanded) ...[
                  const SizedBox(height: 14),
                  const Divider(color: Color(0xFF2A2A3A), height: 1),
                  const SizedBox(height: 12),
                  const Text('STREAK BREAKDOWN',
                      style: TextStyle(fontSize: 10, color: Color(0xFF7A7590), letterSpacing: 0.4)),
                  const SizedBox(height: 10),
                  ...habitDefs.map((h) {
                    final hData = _streaks[h['key']];
                    final hStreak = hData is Map ? (hData['current_streak'] ?? 0) : 0;
                    final lastDone = hData is Map ? (hData['last_done'] ?? '') : '';
                    final isDoneToday = lastDone == today;
                    final longestStreak = hData is Map ? (hData['longest_streak'] ?? 0) : 0;
                    final totalDone = hData is Map ? (hData['total_done'] ?? 0) : 0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(children: [
                        Text(h['icon']!, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h['label']!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            Text('Total: $totalDone days  •  Best: $longestStreak days',
                                style: const TextStyle(fontSize: 10, color: Color(0xFF7A7590))),
                          ],
                        )),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isDoneToday
                                ? const Color(0xFF00D4FF).withOpacity(0.12)
                                : const Color(0xFF2A2A3A),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isDoneToday
                                  ? const Color(0xFF00D4FF).withOpacity(0.4)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(
                              hStreak > 0 ? '🔥' : '—',
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$hStreak day${hStreak == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: hStreak > 0 ? const Color(0xFFF59E0B) : const Color(0xFF7A7590),
                              ),
                            ),
                          ]),
                        ),
                      ]),
                    );
                  }),
                  if (_todayPlan?['top_priority'] != null) ...[
                    const Divider(color: Color(0xFF2A2A3A), height: 1),
                    const SizedBox(height: 10),
                    Row(children: [
                      const Text('🎯 ', style: TextStyle(fontSize: 13)),
                      Expanded(child: Text(
                        "Today's focus: ${_todayPlan!['top_priority']}",
                        style: const TextStyle(fontSize: 12, color: Color(0xFF7A7590), height: 1.4),
                      )),
                    ]),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHabitRow(String habitKey, String icon, String name, String target) {
    final habitData = _streaks[habitKey];
    final streak = habitData is Map ? (habitData['current_streak'] ?? 0) : 0;
    final lastDone = habitData is Map ? (habitData['last_done'] ?? '') : '';
    final today = DateTime.now().toIso8601String().split('T')[0];
    final isDone = lastDone == today;

    return GestureDetector(
      onTap: isDone ? null : () => _markHabitDone(habitKey),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isDone
              ? const Color(0xFF00D4FF).withOpacity(0.08)
              : const Color(0xFF16161F),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDone
                ? const Color(0xFF00D4FF).withOpacity(0.4)
                : const Color(0xFF2A2A3A),
          ),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDone ? const Color(0xFF00D4FF) : Colors.white,
                      )),
                  Text(target,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF7A7590))),
                ],
              ),
            ),
            // Always show streak — 0 in dim, >0 in fire color
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                children: [
                  Text(
                    streak > 0 ? '🔥' : '○',
                    style: const TextStyle(fontSize: 14),
                  ),
                  Text(
                    '$streak',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: streak > 0 ? const Color(0xFFF59E0B) : const Color(0xFF7A7590),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone
                    ? const Color(0xFF00D4FF)
                    : const Color(0xFF2A2A3A),
              ),
              child: Icon(
                isDone ? Icons.check : Icons.add,
                size: 16,
                color: isDone ? Colors.black : const Color(0xFF7A7590),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0C0C10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(icon, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF7A7590))),
              Text(value, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

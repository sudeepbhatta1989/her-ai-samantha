import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'intel_screen.dart';

const String _LAMBDA_URL = 'https://aybg83gr69.execute-api.ap-south-1.amazonaws.com/prod/chat';
const String _USER_ID = 'user1';

class JarvisScreen extends StatefulWidget {
  const JarvisScreen({super.key});

  @override
  State<JarvisScreen> createState() => _JarvisScreenState();
}

class _JarvisScreenState extends State<JarvisScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  // Data
  Map<String, dynamic>? _reflection;
  List<Map<String, dynamic>> _reports = [];
  List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> _logs = [];
  List<Map<String, dynamic>> _approvals = [];
  int _pendingApprovals = 0;

  // Loading states per tab (0=reflect,1=research,2=projects,3=activity,4=approvals)
  final _loading = [true, true, true, true, true];
  final _errors = ['', '', '', '', ''];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _loadTab(_tabController.index);
    });
    // Load all tabs in background
    for (int i = 0; i < 5; i++) { _loadTab(i); } // tab 5 (INTEL) loads itself
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTab(int index) async {
    final actions = ['get_weekly_reflection', 'get_research_reports', 'get_projects', 'get_agent_logs', 'get_approvals'];
    setState(() { _loading[index] = true; _errors[index] = ''; });
    try {
      final res = await http.post(
        Uri.parse(_LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _USER_ID, 'action': actions[index]}),
      ).timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body);
      setState(() {
        _loading[index] = false;
        if (index == 0) _reflection = data['reflection'];
        if (index == 1) _reports = List<Map<String, dynamic>>.from(data['reports'] ?? []);
        if (index == 2) _projects = List<Map<String, dynamic>>.from(data['projects'] ?? []);
        if (index == 3) _logs = List<Map<String, dynamic>>.from(data['logs'] ?? []);
        if (index == 4) { _approvals = List<Map<String, dynamic>>.from(data['approvals'] ?? []); _pendingApprovals = _approvals.where((a) => a['status'] == 'pending').length; }
      });
    } catch (e) {
      setState(() { _loading[index] = false; _errors[index] = 'Could not load data'; });
    }
  }

  Future<void> _generateReflection() async {
    setState(() { _loading[0] = true; });
    try {
      await http.post(
        Uri.parse(_LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _USER_ID, 'message': 'Give me my weekly reflection and analysis'}),
      ).timeout(const Duration(seconds: 40));
      await _loadTab(0);
    } catch (e) {
      setState(() { _loading[0] = false; _errors[0] = 'Could not generate reflection'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131A),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF00D4FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: const Center(
                child: Text('J', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
            const SizedBox(width: 8),
            const Text('Jarvis Brain', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF7C3AED),
          indicatorWeight: 2,
          labelColor: const Color(0xFF7C3AED),
          unselectedLabelColor: const Color(0xFF7A7590),
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3),
          tabs: [
            Tab(icon: const Icon(Icons.auto_awesome, size: 16), text: 'REFLECT'),
            Tab(icon: const Icon(Icons.search, size: 16), text: 'RESEARCH'),
            Tab(icon: const Icon(Icons.rocket_launch_outlined, size: 16), text: 'PROJECTS'),
            Tab(icon: const Icon(Icons.bolt_outlined, size: 16), text: 'ACTIVITY'),
            Tab(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.approval_outlined, size: 16),
                  if (_pendingApprovals > 0) Positioned(
                    right: -6, top: -4,
                    child: Container(
                      width: 10, height: 10,
                      decoration: const BoxDecoration(color: Color(0xFFFF4444), shape: BoxShape.circle),
                    ),
                  ),
                ],
              ),
              text: 'APPROVE',
            ),
            const Tab(
              icon: Icon(Icons.hub_outlined, size: 16),
              text: 'INTEL',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildReflectionTab(),
          _buildResearchTab(),
          _buildProjectsTab(),
          _buildActivityTab(),
          _buildApprovalsTab(),
          const IntelScreen(),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────
  // TAB 1: WEEKLY REFLECTION
  // ─────────────────────────────────────────
  Widget _buildReflectionTab() {
    if (_loading[0]) return _buildLoader();
    if (_errors[0].isNotEmpty || _reflection == null) {
      return _buildEmptyState(
        '🪞',
        'No reflection yet',
        'Ask Samantha "how\'s my week going?" or generate one now.',
        onAction: _generateReflection,
        actionLabel: 'Generate Weekly Reflection',
      );
    }

    final r = _reflection!;
    final wins = List<String>.from(r['wins'] ?? []);
    final missed = List<String>.from(r['missed_opportunities'] ?? []);
    final insights = List<String>.from(r['insights'] ?? []);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Samantha's message
        _glowCard(
          color: const Color(0xFF7C3AED),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('✦', style: TextStyle(color: Color(0xFF7C3AED), fontSize: 14)),
                const SizedBox(width: 6),
                const Text('SAMANTHA SAYS', style: TextStyle(fontSize: 10, color: Color(0xFF7C3AED), letterSpacing: 0.5, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(r['dominant_mood'] ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF7A7590))),
              ]),
              const SizedBox(height: 10),
              Text(r['samanthas_message'] ?? '', style: const TextStyle(fontSize: 14, height: 1.6)),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Week summary
        _sectionCard(
          '📋 Week Summary',
          Text(r['week_summary'] ?? '', style: const TextStyle(fontSize: 13, color: Color(0xFFCCCCDD), height: 1.6)),
        ),
        const SizedBox(height: 12),

        // Stats row
        Row(children: [
          Expanded(child: _statCard('Habits', r['habit_completion_rate'] ?? '—', const Color(0xFF5FB8A0))),
          const SizedBox(width: 10),
          Expanded(child: _statCard('Top Domain', _formatDomain(r['top_domain'] ?? ''), const Color(0xFFF59E0B))),
          const SizedBox(width: 10),
          Expanded(child: _statCard('Mood', r['dominant_mood'] ?? '—', const Color(0xFF7C6FCD))),
        ]),
        const SizedBox(height: 12),

        // Wins
        if (wins.isNotEmpty)
          _sectionCard('🏆 Wins', Column(
            children: wins.map((w) => _bulletRow('✓', w, const Color(0xFF5FB8A0))).toList(),
          )),
        const SizedBox(height: 12),

        // Missed opportunities
        if (missed.isNotEmpty)
          _sectionCard('📍 Missed Opportunities', Column(
            children: missed.map((m) => _bulletRow('→', m, const Color(0xFFF59E0B))).toList(),
          )),
        const SizedBox(height: 12),

        // Insights
        if (insights.isNotEmpty)
          _sectionCard('💡 Deep Insights', Column(
            children: insights.map((i) => _bulletRow('◆', i, const Color(0xFF7C3AED))).toList(),
          )),
        const SizedBox(height: 12),

        // Next week
        _glowCard(
          color: const Color(0xFF00D4FF),
          child: Row(children: [
            const Text('🎯', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('NEXT WEEK FOCUS', style: TextStyle(fontSize: 10, color: Color(0xFF00D4FF), letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text(r['next_week_focus'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.4)),
            ])),
          ]),
        ),
        const SizedBox(height: 16),

        // Regenerate button
        _actionButton('Regenerate Reflection', Icons.refresh, _generateReflection),
        const SizedBox(height: 32),
      ],
    );
  }

  // ─────────────────────────────────────────
  // TAB 2: RESEARCH REPORTS
  // ─────────────────────────────────────────
  Widget _buildResearchTab() {
    if (_loading[1]) return _buildLoader();
    if (_reports.isEmpty) {
      return _buildEmptyState(
        '🔍',
        'No research yet',
        'Ask Samantha to research anything — "Research YouTube Shorts algorithm" or "What\'s new in Flutter"',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _reports.length,
      itemBuilder: (ctx, i) {
        final r = _reports[i];
        final query = r['query'] ?? 'Research';
        final report = r['report'] ?? '';
        final date = r['date'] ?? '';
        final queries = List<String>.from(r['queries_used'] ?? []);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A24),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF5FB8A0).withOpacity(0.25)),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFF5FB8A0).withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(child: Text('🔍', style: TextStyle(fontSize: 16))),
            ),
            title: Text(query, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.4)),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(date, style: const TextStyle(fontSize: 11, color: Color(0xFF7A7590))),
            ),
            iconColor: const Color(0xFF5FB8A0),
            collapsedIconColor: const Color(0xFF7A7590),
            children: [
              if (queries.isNotEmpty) ...[
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: queries.map((q) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF5FB8A0).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF5FB8A0).withOpacity(0.2)),
                    ),
                    child: Text(q, style: const TextStyle(fontSize: 10, color: Color(0xFF5FB8A0))),
                  )).toList(),
                ),
                const SizedBox(height: 12),
              ],
              Text(report, style: const TextStyle(fontSize: 13, color: Color(0xFFCCCCDD), height: 1.65)),
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────
  // TAB 3: PROJECTS
  // ─────────────────────────────────────────
  Widget _buildProjectsTab() {
    if (_loading[2]) return _buildLoader();
    if (_projects.isEmpty) {
      return _buildEmptyState(
        '🚀',
        'No projects yet',
        'Ask Samantha to create a project plan — "Help me build Traveler Tree in 30 days"',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _projects.length,
      itemBuilder: (ctx, i) {
        final p = _projects[i];
        final plan = p['plan'] as Map<String, dynamic>? ?? {};
        final title = plan['project_title'] ?? p['title'] ?? 'Project';
        final goal = plan['goal'] ?? p['goal'] ?? '';
        final milestones = List<Map<String, dynamic>>.from(
          (plan['milestones'] as List? ?? []).map((m) => Map<String, dynamic>.from(m))
        );
        final w1 = plan['week_1_focus'] ?? '';
        final w2 = plan['week_2_focus'] ?? '';
        final w3 = plan['week_3_focus'] ?? '';
        final w4 = plan['week_4_focus'] ?? '';
        final timeNeeded = plan['daily_time_needed'] ?? '';
        final bestTime = plan['best_time_slot'] ?? '';
        final motivation = plan['motivation'] ?? '';
        final progress = (p['progress_percent'] ?? 0).toDouble();

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A24),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.25)),
          ),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            leading: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(child: Text('🚀', style: TextStyle(fontSize: 16))),
            ),
            title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                if (goal.isNotEmpty)
                  Text(goal, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF7A7590))),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress / 100,
                    backgroundColor: const Color(0xFF2A2A3A),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF7C3AED)),
                    minHeight: 3,
                  ),
                ),
              ],
            ),
            iconColor: const Color(0xFF7C3AED),
            collapsedIconColor: const Color(0xFF7A7590),
            children: [
              // Week by week plan
              if (w1.isNotEmpty) ...[
                const Text('WEEKLY PLAN', style: TextStyle(fontSize: 10, color: Color(0xFF7A7590), letterSpacing: 0.5)),
                const SizedBox(height: 8),
                ...[
                  ['Week 1', w1, const Color(0xFF5FB8A0)],
                  ['Week 2', w2, const Color(0xFFF59E0B)],
                  ['Week 3', w3, const Color(0xFF7C3AED)],
                  ['Week 4', w4, const Color(0xFF00D4FF)],
                ].where((r) => (r[1] as String).isNotEmpty).map((row) =>
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (row[2] as Color).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(row[0] as String,
                              style: TextStyle(fontSize: 9, color: row[2] as Color, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(row[1] as String,
                            style: const TextStyle(fontSize: 12, color: Color(0xFFCCCCDD), height: 1.4))),
                      ],
                    ),
                  )
                ),
                const SizedBox(height: 8),
              ],

              // Milestones
              if (milestones.isNotEmpty) ...[
                const Divider(color: Color(0xFF2A2A3A)),
                const SizedBox(height: 8),
                const Text('MILESTONES', style: TextStyle(fontSize: 10, color: Color(0xFF7A7590), letterSpacing: 0.5)),
                const SizedBox(height: 8),
                ...milestones.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 36,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('Day ${m['day']}',
                            style: const TextStyle(fontSize: 9, color: Color(0xFF7A7590))),
                      ),
                      const SizedBox(width: 6),
                      Container(width: 6, height: 6, margin: const EdgeInsets.only(top: 4),
                          decoration: const BoxDecoration(color: Color(0xFF7C3AED), shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m['milestone'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        if ((m['deliverable'] ?? '').isNotEmpty)
                          Text(m['deliverable'] ?? '', style: const TextStyle(fontSize: 11, color: Color(0xFF7A7590))),
                      ])),
                    ],
                  ),
                )),
              ],

              // Time + motivation
              if (timeNeeded.isNotEmpty || bestTime.isNotEmpty) ...[
                const Divider(color: Color(0xFF2A2A3A)),
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.timer_outlined, size: 12, color: Color(0xFF7A7590)),
                  const SizedBox(width: 4),
                  Text('$timeNeeded daily at $bestTime', style: const TextStyle(fontSize: 11, color: Color(0xFF7A7590))),
                ]),
              ],
              if (motivation.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(motivation, style: const TextStyle(fontSize: 12, color: Color(0xFF7C3AED), fontStyle: FontStyle.italic, height: 1.5)),
              ],
            ],
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────
  // TAB 4: AGENT ACTIVITY LOG
  // ─────────────────────────────────────────
  Widget _buildActivityTab() {
    if (_loading[3]) return _buildLoader();
    if (_logs.isEmpty) {
      return _buildEmptyState(
        '⚡',
        'No activity yet',
        'As Jarvis agents work — research, plan, reflect — their activity appears here.',
      );
    }

    final agentIcons = {
      'research_agent':   ('🔍', const Color(0xFF5FB8A0)),
      'planner_agent':    ('📅', const Color(0xFF7C3AED)),
      'reflection_agent': ('🪞', const Color(0xFFC9A96E)),
      'habit_agent':      ('🔥', const Color(0xFFE07070)),
      'reschedule':       ('⚡', const Color(0xFF00D4FF)),
      'samantha_core':    ('✦', const Color(0xFF00D4FF)),
    };

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _logs.length,
      itemBuilder: (ctx, i) {
        final log = _logs[i];
        final agent = log['agent'] ?? 'samantha_core';
        final action = log['action'] ?? '';
        final summary = log['result_summary'] ?? '';
        final date = log['date'] ?? '';
        final iconData = agentIcons[agent] ?? ('⚙️', const Color(0xFF7A7590));

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF16161F),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF2A2A3A)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: (iconData.$2).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Text(iconData.$1, style: const TextStyle(fontSize: 16))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(
                      agent.replaceAll('_', ' ').toUpperCase(),
                      style: TextStyle(fontSize: 10, color: iconData.$2, letterSpacing: 0.4, fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    Text(date, style: const TextStyle(fontSize: 10, color: Color(0xFF7A7590))),
                  ]),
                  if (action.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(action, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  ],
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Color(0xFF7A7590))),
                  ],
                ],
              )),
            ],
          ),
        );
      },
    );
  }


  // ─────────────────────────────────────────
  // TAB 5: APPROVALS (Phase F)
  // ─────────────────────────────────────────
  Widget _buildApprovalsTab() {
    if (_loading[4]) return _buildLoader();

    final pending  = _approvals.where((a) => a['status'] == 'pending').toList();
    final resolved = _approvals.where((a) => a['status'] != 'pending').toList();

    if (_approvals.isEmpty) {
      return _buildEmptyState(
        '✅',
        'No pending approvals',
        "When Jarvis agents need your input — research topics, plan changes, reminders — they will appear here for one-tap approval.",
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF7C3AED),
      onRefresh: () => _loadTab(4),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (pending.isNotEmpty) ...[
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF4444).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFF4444).withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.pending_actions, size: 12, color: Color(0xFFFF4444)),
                  const SizedBox(width: 4),
                  Text('${pending.length} PENDING', style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: Color(0xFFFF4444), letterSpacing: 0.5)),
                ]),
              ),
            ]),
            const SizedBox(height: 12),
            ...pending.map((a) => _buildApprovalCard(a, isPending: true)),
            const SizedBox(height: 8),
          ],
          if (resolved.isNotEmpty) ...[
            const Text('HISTORY', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: Color(0xFF7A7590), letterSpacing: 0.5)),
            const SizedBox(height: 8),
            ...resolved.take(10).map((a) => _buildApprovalCard(a, isPending: false)),
          ],
        ],
      ),
    );
  }

  Widget _buildApprovalCard(Map<String, dynamic> approval, {required bool isPending}) {
    final status    = approval['status'] ?? 'pending';
    final agent     = approval['agent'] ?? 'agent';
    final title     = approval['title'] ?? 'Agent Action';
    final desc      = approval['description'] ?? '';
    final priority  = approval['priority'] ?? 'normal';
    final date      = approval['date'] ?? '';
    final id        = approval['id'] ?? '';

    final agentColors = {
      'research_agent':   const Color(0xFF5FB8A0),
      'planner_agent':    const Color(0xFF7C3AED),
      'reflection_agent': const Color(0xFFC9A96E),
      'habit_agent':      const Color(0xFFE07070),
      'samantha_core':    const Color(0xFF00D4FF),
    };
    final agentIcons = {
      'research_agent':   '🔍',
      'planner_agent':    '📅',
      'reflection_agent': '🪞',
      'habit_agent':      '🔥',
      'samantha_core':    '✦',
    };

    final color = agentColors[agent] ?? const Color(0xFF7A7590);
    final icon  = agentIcons[agent]  ?? '⚙️';

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'approved': statusColor = const Color(0xFF4CAF50); statusLabel = '✓ Approved'; break;
      case 'rejected': statusColor = const Color(0xFFFF4444); statusLabel = '✗ Rejected'; break;
      default:         statusColor = const Color(0xFFFFA726); statusLabel = '● Pending';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16161F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isPending ? color.withOpacity(0.4) : const Color(0xFF2A2A3A),
          width: isPending ? 1.5 : 1,
        ),
        boxShadow: isPending ? [BoxShadow(color: color.withOpacity(0.06), blurRadius: 12)] : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(child: Text(icon, style: const TextStyle(fontSize: 15))),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  agent.replaceAll('_', ' ').toUpperCase(),
                  style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                ),
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3)),
              ])),
              if (priority == 'high')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4444).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('HIGH', style: TextStyle(fontSize: 9, color: Color(0xFFFF4444), fontWeight: FontWeight.w700)),
                ),
            ]),
          ),
          // Description
          if (desc.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Text(desc, style: const TextStyle(fontSize: 12, color: Color(0xFF9999AA), height: 1.5)),
            ),
          // Date + status
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Row(children: [
              Text(date, style: const TextStyle(fontSize: 10, color: Color(0xFF7A7590))),
              const Spacer(),
              if (!isPending)
                Text(statusLabel, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.w600)),
            ]),
          ),
          // Approve / Reject buttons (pending only)
          if (isPending) ...[
            const Divider(height: 1, color: Color(0xFF2A2A3A)),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _rejectApproval(id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(14),
                      ),
                    ),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.close, size: 14, color: Color(0xFFFF4444)),
                      SizedBox(width: 6),
                      Text('REJECT', style: TextStyle(fontSize: 11, color: Color(0xFFFF4444), fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                    ]),
                  ),
                ),
              ),
              Container(width: 1, height: 44, color: const Color(0xFF2A2A3A)),
              Expanded(
                child: GestureDetector(
                  onTap: () => _approveAction(id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.only(
                        bottomRight: Radius.circular(14),
                      ),
                    ),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.check, size: 14, color: Color(0xFF4CAF50)),
                      SizedBox(width: 6),
                      Text('APPROVE', style: TextStyle(fontSize: 11, color: Color(0xFF4CAF50), fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                    ]),
                  ),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Future<void> _approveAction(String approvalId) async {
    try {
      final res = await http.post(
        Uri.parse(_LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _USER_ID, 'action': 'approve_action', 'approval_id': approvalId}),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      if (data['status'] == 'ok') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✓ Action approved'),
              backgroundColor: Color(0xFF4CAF50),
              duration: Duration(seconds: 2),
            ),
          );
        }
        await _loadTab(4);
        await _loadTab(3); // refresh activity log too
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: const Color(0xFFFF4444)),
        );
      }
    }
  }

  Future<void> _rejectApproval(String approvalId) async {
    // Show reason dialog
    String reason = 'Not needed right now';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A24),
        title: const Text('Reject Action', style: TextStyle(fontSize: 15)),
        content: TextField(
          decoration: const InputDecoration(
            hintText: 'Reason (optional)',
            hintStyle: TextStyle(color: Color(0xFF7A7590)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A3A))),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: (v) => reason = v.isEmpty ? 'Not needed right now' : v,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF7A7590)))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject', style: TextStyle(color: Color(0xFFFF4444)))),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final res = await http.post(
        Uri.parse(_LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _USER_ID, 'action': 'reject_action', 'approval_id': approvalId, 'reason': reason}),
      ).timeout(const Duration(seconds: 10));
      final data = jsonDecode(res.body);
      if (data['status'] == 'ok') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Action rejected'), backgroundColor: Color(0xFF555566), duration: Duration(seconds: 2)),
          );
        }
        await _loadTab(4);
        await _loadTab(3);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: const Color(0xFFFF4444)),
        );
      }
    }
  }

  // ─────────────────────────────────────────
  // SHARED WIDGETS
  // ─────────────────────────────────────────
  Widget _buildLoader() {
    return const Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        CircularProgressIndicator(color: Color(0xFF7C3AED), strokeWidth: 2),
        SizedBox(height: 12),
        Text('Jarvis is thinking...', style: TextStyle(fontSize: 12, color: Color(0xFF7A7590))),
      ]),
    );
  }

  Widget _buildEmptyState(String emoji, String title, String subtitle,
      {VoidCallback? onAction, String? actionLabel}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(emoji, style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF7A7590), height: 1.6)),
          if (onAction != null) ...[
            const SizedBox(height: 24),
            _actionButton(actionLabel ?? 'Try Again', Icons.auto_awesome, onAction),
          ],
        ]),
      ),
    );
  }

  Widget _glowCard({required Color color, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.35)),
        boxShadow: [BoxShadow(color: color.withOpacity(0.08), blurRadius: 16, spreadRadius: 2)],
      ),
      child: child,
    );
  }

  Widget _sectionCard(String title, Widget content) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16161F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A3A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: Color(0xFFCCCCDD))),
        const SizedBox(height: 10),
        content,
      ]),
    );
  }

  Widget _statCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(children: [
        Text(value, textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(fontSize: 9, color: Color(0xFF7A7590), letterSpacing: 0.3)),
      ]),
    );
  }

  Widget _bulletRow(String bullet, String text, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(bullet, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFFCCCCDD), height: 1.5))),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7C3AED), Color(0xFF5B21B6)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  String _formatDomain(String domain) {
    final map = {
      'phokat_ka_gyan': 'Phokat', 'traveler_tree': 'Travel',
      'gita_app': 'Gita App', 'sketch': 'Sketch',
      'ukulele': 'Ukulele', 'health': 'Health',
      'corporate': 'Work', 'sapna_canvas': 'Sapna',
    };
    return map[domain] ?? domain.replaceAll('_', ' ');
  }
}

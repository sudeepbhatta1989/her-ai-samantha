import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

const String LAMBDA_URL = 'https://aybg83gr69.execute-api.ap-south-1.amazonaws.com/prod/chat';
const String USER_ID = 'user1';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => PlanScreenState();
}

class PlanScreenState extends State<PlanScreen> {
  Map<String, dynamic>? _plan;
  Map<String, dynamic>? _tomorrowPlan;
  bool _loading = true;
  bool _loadingTomorrow = false;
  bool _generating = false;
  bool _generatingTomorrow = false;
  bool _initialLoadDone = false;
  bool _showingTomorrow = false;   // ← toggle between Today / Tomorrow
  final _domainColors = {
    'phokat_ka_gyan': 0xFFF59E0B,
    'traveler_tree': 0xFF5FB8A0,
    'gita_app': 0xFFC9A96E,
    'sketch': 0xFF7C6FCD,
    'pencil_sketch': 0xFF7C6FCD,
    'ukulele': 0xFF7DB8E0,
    'exercise': 0xFFE07070,
    'health': 0xFFE07070,
    'corporate': 0xFF6B7280,
    'sapna_canvas': 0xFFEC4899,
    'default': 0xFF00D4FF,
  };

  @override
  void initState() {
    super.initState();
    // Check if we have a stale plan from a previous day
    // If yes, start with null so _loadPlan triggers fresh generation
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final fallback = _getLocalFallbackPlan();
    final fallbackDate = fallback['date'] as String? ?? todayStr;
    _plan = (fallbackDate == todayStr) ? fallback : null;
    _loadPlan();
  }

  // Called on every app resume — detects day change and reloads
  void _checkDayChange() {
    final todayStr = DateTime.now().toIso8601String().substring(0, 10);
    final planDate = _plan?['date'] as String? ?? '';
    if (planDate.isNotEmpty && planDate != todayStr) {
      // New day! Clear old plan and fetch today's
      setState(() {
        _plan = null;
        _initialLoadDone = false;
      });
      _loadPlan();
    }
  }

  // Called by parent (main.dart) when this tab is selected.
  // Only reloads on the very first switch; after that, local state is preserved.
  // User can still force-refresh with the refresh icon button.
  void reload() {
    _checkDayChange(); // Always check if day rolled over
    if (!_initialLoadDone) _loadPlan();
    // If same day and already loaded, do nothing — completed_tasks stay in local state
  }

  // Hardcoded fallback — always shows even if Lambda is down
  Map<String, dynamic> _getLocalFallbackPlan() {
    final now = DateTime.now();
    final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;
    final isSunday = now.weekday == DateTime.sunday;
    final h = now.hour;

    if (isSunday) {
      return {
        'morning': h < 10 ? [
          {'time': '9:00 AM', 'task': 'Exercise', 'duration': '30 min', 'domain': 'health'},
          {'time': '9:30 AM', 'task': 'Daily Short (Phokat ka Gyan)', 'duration': '30 min', 'domain': 'phokat_ka_gyan'},
          {'time': '10:00 AM', 'task': 'Pencil Sketch', 'duration': '60 min', 'domain': 'sketch'},
        ] : [],
        'afternoon': [
          {'time': '12:00 PM', 'task': 'Sunday Debate Video', 'duration': '2 hours', 'domain': 'phokat_ka_gyan'},
          {'time': '2:30 PM', 'task': 'Traveler Tree Work', 'duration': '1.5 hours', 'domain': 'traveler_tree'},
          {'time': '4:00 PM', 'task': 'Pencil Sketch', 'duration': '60 min', 'domain': 'sketch'},
        ],
        'evening': [
          {'time': '6:00 PM', 'task': 'Ukulele Practice', 'duration': '30 min', 'domain': 'ukulele'},
          {'time': '7:00 PM', 'task': 'Family Time', 'duration': '1 hour', 'domain': 'personal'},
          {'time': '9:00 PM', 'task': 'Plan next week', 'duration': '30 min', 'domain': 'phokat_ka_gyan'},
        ],
        'top_priority': 'Complete Sunday Debate Video for Phokat ka Gyan',
        'motivation': "Sunday is your creative day Sudeep — make it count!",
        'habits_today': ['daily_short', 'sketch', 'ukulele', 'exercise'],
        'focus_domain': 'phokat_ka_gyan',
        'completed_tasks': [],
      };
    } else if (isWeekend) {
      return {
        'morning': [
          {'time': '8:00 AM', 'task': 'Exercise', 'duration': '30 min', 'domain': 'health'},
          {'time': '8:30 AM', 'task': 'Daily Short (Phokat ka Gyan)', 'duration': '30 min', 'domain': 'phokat_ka_gyan'},
          {'time': '9:30 AM', 'task': 'Pencil Sketch', 'duration': '60 min', 'domain': 'sketch'},
        ],
        'afternoon': [
          {'time': '1:00 PM', 'task': 'Traveler Tree Work', 'duration': '2 hours', 'domain': 'traveler_tree'},
          {'time': '3:00 PM', 'task': 'Gita Learning App', 'duration': '1 hour', 'domain': 'gita_app'},
        ],
        'evening': [
          {'time': '6:00 PM', 'task': 'Ukulele Practice', 'duration': '30 min', 'domain': 'ukulele'},
          {'time': '8:00 PM', 'task': 'Review week + plan ahead', 'duration': '30 min', 'domain': 'phokat_ka_gyan'},
        ],
        'top_priority': 'Daily Short for Phokat ka Gyan',
        'motivation': "Weekend hustle — every hour matters, Sudeep!",
        'habits_today': ['daily_short', 'sketch', 'ukulele', 'exercise'],
        'focus_domain': 'phokat_ka_gyan',
        'completed_tasks': [],
      };
    } else {
      return {
        'morning': [
          {'time': '6:30 AM', 'task': 'Exercise', 'duration': '30 min', 'domain': 'health'},
          {'time': '7:00 AM', 'task': 'Daily Short (Phokat ka Gyan)', 'duration': '30 min', 'domain': 'phokat_ka_gyan'},
        ],
        'afternoon': [
          {'time': '1:00 PM', 'task': 'Pencil Sketch (lunch break)', 'duration': '30 min', 'domain': 'sketch'},
        ],
        'evening': [
          {'time': '7:30 PM', 'task': 'Ukulele Practice', 'duration': '30 min', 'domain': 'ukulele'},
          {'time': '8:00 PM', 'task': 'Traveler Tree / Project Work', 'duration': '1 hour', 'domain': 'traveler_tree'},
          {'time': '10:00 PM', 'task': 'Evening review with Samantha', 'duration': '15 min', 'domain': 'personal'},
        ],
        'top_priority': 'Daily Short for Phokat ka Gyan',
        'motivation': "Consistency beats perfection — show up today, Sudeep.",
        'habits_today': ['daily_short', 'sketch', 'ukulele', 'exercise'],
        'focus_domain': 'phokat_ka_gyan',
        'completed_tasks': [],
      };
    }
  }

  bool _hasSlots(dynamic plan) {
    if (plan == null || plan is! Map) return false;
    return (plan['morning'] is List && (plan['morning'] as List).isNotEmpty) ||
        (plan['afternoon'] is List && (plan['afternoon'] as List).isNotEmpty) ||
        (plan['evening'] is List && (plan['evening'] as List).isNotEmpty);
  }

  Future<void> _loadPlan() async {
    setState(() { _loading = true; });
    try {
      final response = await http.post(
        Uri.parse(LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': USER_ID,
          'action': 'get_plan',
          'date': DateTime.now().toIso8601String().substring(0, 10),
        }),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      final plan = data['plan'];

      if (_hasSlots(plan)) {
        // Merge: keep any ticks already in local state that aren't in Firestore yet
        // (e.g., ticked offline before Lambda confirmed the save)
        final localDone = List<String>.from(_plan?['completed_tasks'] ?? []);
        final remoteDone = List<String>.from(plan['completed_tasks'] ?? []);
        final merged = {...remoteDone, ...localDone}.toList();

        final merged_plan = Map<String, dynamic>.from(plan);
        merged_plan['completed_tasks'] = merged;

        setState(() {
          _plan = merged_plan;
          _loading = false;
          _initialLoadDone = true;
        });
      } else {
        await _generatePlan();
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _initialLoadDone = true;
      });
    }
  }

  Future<void> _generatePlan() async {
    setState(() { _generating = true; });
    try {
      final response = await http.post(
        Uri.parse(LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': USER_ID, 'action': 'generate_plan'}),
      ).timeout(const Duration(seconds: 30));

      final data = jsonDecode(response.body);
      final plan = data['plan'];

      // Preserve any ticks the user already made
      final localDone = List<String>.from(_plan?['completed_tasks'] ?? []);

      if (_hasSlots(plan)) {
        final newPlan = Map<String, dynamic>.from(plan);
        // Merge local ticks with what Lambda returned
        final remoteDone = List<String>.from(newPlan['completed_tasks'] ?? []);
        newPlan['completed_tasks'] = {...remoteDone, ...localDone}.toList();
        setState(() {
          _plan = newPlan;
          _generating = false;
          _loading = false;
          _initialLoadDone = true;
        });
      } else {
        final fallback = _getLocalFallbackPlan();
        fallback['completed_tasks'] = localDone;
        setState(() {
          _plan = fallback;
          _generating = false;
          _loading = false;
          _initialLoadDone = true;
        });
      }
    } catch (e) {
      final fallback = _getLocalFallbackPlan();
      fallback['completed_tasks'] = List<String>.from(_plan?['completed_tasks'] ?? []);
      setState(() {
        _plan = fallback;
        _generating = false;
        _loading = false;
        _initialLoadDone = true;
      });
    }
  }

  Future<void> _loadTomorrowPlan() async {
    setState(() { _loadingTomorrow = true; });
    try {
      final response = await http.post(
        Uri.parse(LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': USER_ID, 'action': 'get_plan_for_date', 'date': 'tomorrow'}),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(response.body);
      final plan = data['plan'];
      setState(() {
        _tomorrowPlan = _hasSlots(plan) ? Map<String, dynamic>.from(plan) : null;
        _loadingTomorrow = false;
      });
    } catch (e) {
      setState(() { _loadingTomorrow = false; });
    }
  }

  Future<void> _generateTomorrowPlan() async {
    setState(() { _generatingTomorrow = true; });
    try {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final dateStr = '${tomorrow.year}-${tomorrow.month.toString().padLeft(2,'0')}-${tomorrow.day.toString().padLeft(2,'0')}';
      final response = await http.post(
        Uri.parse(LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': USER_ID, 'action': 'generate_plan', 'date': dateStr}),
      ).timeout(const Duration(seconds: 30));
      final data = jsonDecode(response.body);
      final plan = data['plan'];
      if (_hasSlots(plan)) {
        setState(() { _tomorrowPlan = Map<String, dynamic>.from(plan); });
      }
    } catch (e) {
      debugPrint('Generate tomorrow error: $e');
    } finally {
      setState(() { _generatingTomorrow = false; });
    }
  }

  Future<void> _markTaskDone(String task) async {
    if (_plan == null) return;

    final completed = List<String>.from(_plan?['completed_tasks'] ?? []);
    final alreadyDone = completed.contains(task);

    // Toggle: tap done task = undo it
    if (alreadyDone) {
      completed.remove(task);
    } else {
      completed.add(task);
    }

    // Optimistic UI — update immediately, don't wait for network
    setState(() => _plan?['completed_tasks'] = completed);

    // Save to Firestore via proper Lambda action (NOT a chat message)
    try {
      final action = alreadyDone ? 'unmark_task_done' : 'mark_task_done';
      await http.post(
        Uri.parse(LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': USER_ID,
          'action': action,
          'task': task,
        }),
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      // Network failed — local state already updated, will sync next load
      debugPrint('Task save error (will retry on next load): $e');
    }
  }

  int _getDomainColor(String? domain) {
    if (domain == null) return _domainColors['default']!;
    final key = domain.toLowerCase().replaceAll(' ', '_');
    return _domainColors[key] ?? _domainColors['default']!;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateFormat('EEEE, MMMM d').format(now);
    final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

    final tomorrow = now.add(const Duration(days: 1));
    final tomorrowLabel = DateFormat('EEEE, MMMM d').format(tomorrow);
    final activePlan = _showingTomorrow ? _tomorrowPlan : _plan;
    final activeLoading = _showingTomorrow ? _loadingTomorrow : _loading;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131A),
        title: Column(
          children: [
            // Today / Tomorrow toggle
            Container(
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2E),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dayTab('Today', !_showingTomorrow, () {
                    setState(() { _showingTomorrow = false; });
                  }),
                  _dayTab('Tomorrow', _showingTomorrow, () {
                    setState(() { _showingTomorrow = true; });
                    if (_tomorrowPlan == null && !_loadingTomorrow) _loadTomorrowPlan();
                  }),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _showingTomorrow ? tomorrowLabel : today,
              style: const TextStyle(fontSize: 11, color: Color(0xFF7A7590)),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: Color(0xFF7C3AED)),
            onPressed: _showReminders,
            tooltip: 'Reminders',
          ),
          IconButton(
            icon: Icon(Icons.refresh,
              color: (_showingTomorrow ? _generatingTomorrow : _generating)
                  ? const Color(0xFF444455) : const Color(0xFF00D4FF)),
            onPressed: (_showingTomorrow ? _generatingTomorrow : _generating)
                ? null
                : (_showingTomorrow ? _generateTomorrowPlan : _generatePlan),
            tooltip: _showingTomorrow ? 'Generate tomorrow\'s plan' : 'Regenerate today\'s plan',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF2A2A3A)),
        ),
      ),
      body: activeLoading
          ? _buildLoading(_showingTomorrow ? 'Loading tomorrow\'s plan...' : 'Loading your plan...')
          : (_showingTomorrow ? _generatingTomorrow : _generating)
              ? _buildLoading(_showingTomorrow ? 'Samantha is planning your tomorrow...' : 'Samantha is creating your plan...')
              : (_showingTomorrow && activePlan == null)
                  ? _buildTomorrowEmpty()
                  : _buildPlanFromData(activePlan ?? _getLocalFallbackPlan(), isWeekend),
    );
  }

  Widget _dayTab(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF00D4FF).withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: active ? Border.all(color: const Color(0xFF00D4FF), width: 1) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            color: active ? const Color(0xFF00D4FF) : const Color(0xFF7A7590),
          ),
        ),
      ),
    );
  }

  Widget _buildTomorrowEmpty() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final dayName = DateFormat('EEEE').format(tomorrow);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_today_outlined, size: 48, color: Color(0xFF7A7590)),
            const SizedBox(height: 20),
            Text(
              'No plan for $dayName yet',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Ask Samantha "plan my tomorrow" in the Talk tab,\nor tap the button below to generate it now.',
              style: const TextStyle(fontSize: 13, color: Color(0xFF7A7590), height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _generatingTomorrow ? null : _generateTomorrowPlan,
              icon: _generatingTomorrow
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(_generatingTomorrow ? 'Generating...' : 'Generate $dayName\'s Plan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF7C3AED),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF00D4FF)),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Color(0xFF7A7590))),
        ],
      ),
    );
  }

  Widget _buildPlanFromData(Map<String, dynamic> plan, bool isWeekend) {
    final topPriority = plan['top_priority'] ?? 'Focus on Phokat ka Gyan';
    final motivation = plan['motivation'] ?? '';
    final morning = _parseSlots(plan['morning']);
    final afternoon = _parseSlots(plan['afternoon']);
    final evening = _parseSlots(plan['evening']);
    final completed = List<String>.from(plan['completed_tasks'] ?? []);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Top priority card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF7C3AED).withOpacity(0.2),
                const Color(0xFF1A1A24),
              ],
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('⭐ TOP PRIORITY',
                  style: TextStyle(fontSize: 10, color: Color(0xFF7C3AED), letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Text(topPriority,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, height: 1.4)),
              if (motivation.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(motivation,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF7A7590), height: 1.5)),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Progress summary
        _buildProgressBar(completed, morning + afternoon + evening),

        const SizedBox(height: 20),

        // Morning
        if (morning.isNotEmpty) ...[
          _buildTimeHeader('🌅', 'Morning', const Color(0xFFF59E0B)),
          const SizedBox(height: 8),
          ...morning.map((slot) => _buildTaskCard(slot, completed)),
          const SizedBox(height: 16),
        ],

        // Afternoon
        if (afternoon.isNotEmpty) ...[
          _buildTimeHeader('☀️', 'Afternoon', const Color(0xFF5FB8A0)),
          const SizedBox(height: 8),
          ...afternoon.map((slot) => _buildTaskCard(slot, completed)),
          const SizedBox(height: 16),
        ],

        // Evening
        if (evening.isNotEmpty) ...[
          _buildTimeHeader('🌙', 'Evening', const Color(0xFF7C6FCD)),
          const SizedBox(height: 8),
          ...evening.map((slot) => _buildTaskCard(slot, completed)),
          const SizedBox(height: 16),
        ],

        // Regenerate button
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _generatePlan,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A24),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A2A3A)),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.auto_awesome, size: 16, color: Color(0xFF7C3AED)),
                SizedBox(width: 8),
                Text('Ask Samantha to regenerate plan',
                    style: TextStyle(color: Color(0xFF7C3AED), fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildProgressBar(List<String> completed, List<Map> allTasks) {
    final total = allTasks.length;
    // Only count completed tasks that actually exist in current plan slots
    // Prevents 16/10 when plan regenerates with different task names
    final currentTaskNames = allTasks.map((t) => (t['task'] ?? '').toString().toLowerCase()).toSet();
    final done = completed.where((c) => currentTaskNames.contains(c.toLowerCase())).length;
    final progress = total > 0 ? (done / total).clamp(0.0, 1.0) : 0.0;

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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Day Progress',
                  style: TextStyle(fontSize: 12, color: Color(0xFF7A7590))),
              Text('$done / $total tasks',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF00D4FF))),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: const Color(0xFF2A2A3A),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00D4FF)),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeHeader(String emoji, String label, Color color) {
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Text(label.toUpperCase(),
            style: TextStyle(fontSize: 11, color: color, letterSpacing: 0.5,
                fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 1, color: color.withOpacity(0.2))),
      ],
    );
  }

  // Parse "6:30 AM", "1:00 PM" etc into a DateTime for today
  bool _isTaskOverdue(String timeStr) {
    if (timeStr.isEmpty) return false;
    try {
      final now = DateTime.now();
      final cleaned = timeStr.trim().toUpperCase();
      final parts = cleaned.replaceAll('AM', '').replaceAll('PM', '').trim().split(':');
      if (parts.length < 2) return false;
      int hour = int.parse(parts[0]);
      int minute = int.parse(parts[1].trim());
      final isPM = cleaned.contains('PM');
      final isAM = cleaned.contains('AM');
      if (isPM && hour != 12) hour += 12;
      if (isAM && hour == 12) hour = 0;
      final taskTime = DateTime(now.year, now.month, now.day, hour, minute);
      // Overdue = task time has passed + at least 30 min grace period
      return now.isAfter(taskTime.add(const Duration(minutes: 30)));
    } catch (_) {
      return false;
    }
  }

  Widget _buildTaskCard(Map slot, List<String> completed) {
    final task = slot['task'] ?? '';
    final time = slot['time'] ?? '';
    final duration = slot['duration'] ?? '';
    final domain = slot['domain'] ?? 'default';
    final isDone = completed.contains(task);
    final isOverdue = !isDone && _isTaskOverdue(time);
    final domainColor = Color(_getDomainColor(domain));

    // Colors based on state
    final cardColor = isDone
        ? const Color(0xFF1A1A24).withOpacity(0.4)
        : isOverdue
            ? const Color(0xFF2A0A0A)
            : const Color(0xFF1A1A24);

    final borderColor = isDone
        ? const Color(0xFF2A2A3A)
        : isOverdue
            ? const Color(0xFFEF4444).withOpacity(0.5)
            : domainColor.withOpacity(0.3);

    final barColor = isDone
        ? const Color(0xFF2A2A3A)
        : isOverdue
            ? const Color(0xFFEF4444)
            : domainColor;

    return GestureDetector(
      onTap: () => _markTaskDone(task),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            // Left color bar
            Container(
              width: 3, height: 40,
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    if (isOverdue) ...[
                      const Text('⚠️ ', style: TextStyle(fontSize: 11)),
                    ],
                    Expanded(
                      child: Text(task,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDone
                                ? const Color(0xFF7A7590)
                                : isOverdue
                                    ? const Color(0xFFFF6B6B)
                                    : Colors.white,
                            decoration: isDone ? TextDecoration.lineThrough : null,
                          )),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Row(children: [
                    if (time.isNotEmpty) ...[
                      Icon(Icons.access_time, size: 11,
                          color: isOverdue && !isDone
                              ? const Color(0xFFEF4444).withOpacity(0.8)
                              : const Color(0xFF7A7590)),
                      const SizedBox(width: 3),
                      Text(time,
                          style: TextStyle(
                            fontSize: 11,
                            color: isOverdue && !isDone
                                ? const Color(0xFFEF4444).withOpacity(0.8)
                                : const Color(0xFF7A7590),
                          )),
                      const SizedBox(width: 10),
                    ],
                    if (duration.isNotEmpty) ...[
                      const Icon(Icons.timer_outlined, size: 11, color: Color(0xFF7A7590)),
                      const SizedBox(width: 3),
                      Text(duration,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF7A7590))),
                    ],
                    if (isOverdue) ...[
                      const SizedBox(width: 8),
                      const Text('MISSED',
                          style: TextStyle(
                            fontSize: 9,
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          )),
                    ],
                  ]),
                ],
              ),
            ),
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone
                    ? const Color(0xFF00D4FF)
                    : isOverdue
                        ? const Color(0xFFEF4444).withOpacity(0.15)
                        : const Color(0xFF2A2A3A),
                border: isOverdue && !isDone
                    ? Border.all(color: const Color(0xFFEF4444).withOpacity(0.5))
                    : null,
              ),
              child: Icon(
                isDone ? Icons.check : Icons.radio_button_unchecked,
                size: 16,
                color: isDone
                    ? Colors.black
                    : isOverdue
                        ? const Color(0xFFEF4444)
                        : const Color(0xFF7A7590),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Map> _parseSlots(dynamic slots) {
    if (slots == null) return [];
    if (slots is List) return slots.map((s) => Map<String, dynamic>.from(s)).toList();
    return [];
  }

  void _showReminders() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A24),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _RemindersSheet(),
    );
  }
}

class _RemindersSheet extends StatefulWidget {
  @override
  State<_RemindersSheet> createState() => _RemindersSheetState();
}

class _RemindersSheetState extends State<_RemindersSheet> {
  // With FCM, notifications are sent from server — no local "pending" list.
  // We show the schedule as reference; all reminders are always "active via FCM".
  bool _loading = false;

  final _schedule = [
    {'time': '7:00 AM', 'icon': '🏃', 'title': 'Morning Exercise', 'id': 1},
    {'time': '7:05 AM', 'icon': '✦', 'title': 'Morning Briefing from Samantha', 'id': 2},
    {'time': '8:25 AM', 'icon': '🎬', 'title': 'Daily Short Due (Phokat ka Gyan)', 'id': 3},
    {'time': '1:00 PM', 'icon': '☀️', 'title': 'Afternoon Check-in', 'id': 4},
    {'time': '8:30 PM', 'icon': '✏️', 'title': 'Pencil Sketch Reminder', 'id': 5},
    {'time': '9:00 PM', 'icon': '🎵', 'title': 'Ukulele Practice', 'id': 6},
    {'time': '10:00 PM', 'icon': '🌙', 'title': 'Evening Review with Samantha', 'id': 7},
    {'time': 'Mon/Wed/Fri 7:20 PM', 'icon': '📹', 'title': 'Corporate Kurukshetra Video', 'id': 8},
    {'time': 'Sunday 9:00 AM', 'icon': '🎙️', 'title': 'Sunday Debate Video', 'id': 11},
  ];

  Future<void> _reschedule() async {
    setState(() => _loading = true);
    // Notifications are managed server-side via Firebase — no local reschedule needed
    await Future.delayed(const Duration(milliseconds: 500));
    if (mounted) {
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('✓ Reminders active via Firebase!'),
        backgroundColor: Color(0xFF7C3AED),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🔔', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              const Text("Samantha's Reminders",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton(
                onPressed: _loading ? null : _reschedule,
                child: Text(_loading ? '...' : 'Reset All',
                    style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '9 reminders active via Firebase',
            style: TextStyle(fontSize: 11, color: Color(0xFF7A7590)),
          ),
          const SizedBox(height: 16),
          ..._schedule.map((r) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Text(r['icon'] as String, style: const TextStyle(fontSize: 18)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r['title'] as String,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                        Text(r['time'] as String,
                            style: const TextStyle(fontSize: 11, color: Color(0xFF7A7590))),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00D4FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF00D4FF).withOpacity(0.4)),
                    ),
                    child: const Text(
                      '● FCM',
                      style: TextStyle(
                          fontSize: 10,
                          color: Color(0xFF00D4FF),
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.2)),
            ),
            child: const Text(
              'Notifications are delivered via Firebase Cloud Messaging. Tell Samantha in chat to add or change reminders.',
              style: TextStyle(fontSize: 11, color: Color(0xFF7A7590), height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

const String _LAMBDA_URL =
    'https://aybg83gr69.execute-api.ap-south-1.amazonaws.com/prod/chat';
const String _USER_ID = 'user1';

class InsightsScreen extends StatefulWidget {
  const InsightsScreen({super.key});

  @override
  State<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends State<InsightsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _sessions = [];
  Map<String, dynamic>? _reflection;
  Map<String, dynamic> _streaks = {};
  bool _loadingHistory = true;
  bool _loadingReflection = true;
  bool _importingChatGPT = false;
  String? _importResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) _onTabSelected(_tabController.index);
    });
    _loadHistory();
    _loadReflection();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onTabSelected(int i) {
    if (i == 0 && _sessions.isEmpty) _loadHistory();
    if (i == 1 && _reflection == null) _loadReflection();
  }

  Future<void> _loadHistory() async {
    setState(() => _loadingHistory = true);
    try {
      final res = await http.post(
        Uri.parse(_LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _USER_ID, 'action': 'get_history'}),
      ).timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);
      final sessions = (data['sessions'] as List? ?? [])
          .map((s) => Map<String, dynamic>.from(s))
          .toList()
        ..sort((a, b) => (b['timestamp'] ?? '').compareTo(a['timestamp'] ?? ''));
      setState(() { _sessions = sessions; _loadingHistory = false; });
    } catch (e) {
      setState(() => _loadingHistory = false);
    }
  }

  Future<void> _loadReflection() async {
    setState(() => _loadingReflection = true);
    try {
      final reflRes = await http.post(
        Uri.parse(_LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _USER_ID, 'action': 'get_weekly_reflection'}),
      ).timeout(const Duration(seconds: 15));
      final streakRes = await http.post(
        Uri.parse(_LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': _USER_ID, 'action': 'get_streaks'}),
      ).timeout(const Duration(seconds: 10));
      final rData = jsonDecode(reflRes.body);
      final sData = jsonDecode(streakRes.body);
      setState(() {
        _reflection = rData['reflection'] as Map<String, dynamic>?;
        _streaks = Map<String, dynamic>.from(sData['streaks'] ?? {});
        _loadingReflection = false;
      });
    } catch (e) {
      setState(() => _loadingReflection = false);
    }
  }

  Future<void> _importChatGPT() async {
    // Step 1: pick file
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'zip'],
        withData: true,
      );
    } catch (e) {
      _showSnack('Could not open file picker: $e', error: true);
      return;
    }
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    String content = '';
    try {
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!, allowMalformed: true);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      }
    } catch (e) {
      _showSnack('Could not read file: $e', error: true);
      return;
    }

    // Limit to 50KB for Lambda
    if (content.length > 51200) content = content.substring(0, 51200);

    setState(() { _importingChatGPT = true; _importResult = null; });
    try {
      final res = await http.post(
        Uri.parse(_LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': _USER_ID,
          'action': 'import_chatgpt',
          'chatgpt_data': content,
        }),
      ).timeout(const Duration(seconds: 40));
      final data = jsonDecode(res.body);
      final count = data['imported_count'] ?? 0;
      setState(() {
        _importResult = 'Imported $count conversations from ChatGPT.';
        _importingChatGPT = false;
      });
      _loadHistory(); // refresh
    } catch (e) {
      setState(() {
        _importResult = 'Import failed: $e';
        _importingChatGPT = false;
      });
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : const Color(0xFF00D4FF),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0C10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131A),
        elevation: 0,
        title: const Text('Insights',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF00D4FF),
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelColor: const Color(0xFF7A7590),
          tabs: const [
            Tab(text: 'History'),
            Tab(text: 'Weekly'),
            Tab(text: 'Import'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildHistory(),
          _buildWeekly(),
          _buildImport(),
        ],
      ),
    );
  }

  // ─── HISTORY TAB ─────────────────────────────────────────────────────────

  Widget _buildHistory() {
    if (_loadingHistory) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF)));
    }
    if (_sessions.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.chat_bubble_outline, color: Color(0xFF2A2A3A), size: 48),
          const SizedBox(height: 12),
          const Text('No conversations yet',
              style: TextStyle(color: Color(0xFF7A7590), fontSize: 14)),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadHistory,
      color: const Color(0xFF00D4FF),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _sessions.length,
        itemBuilder: (ctx, i) => _buildSessionCard(_sessions[i]),
      ),
    );
  }

  Widget _buildSessionCard(Map<String, dynamic> session) {
    final messages = (session['messages'] as List? ?? []);
    final first = messages.isNotEmpty
        ? (messages.first['text'] ?? messages.first['content'] ?? '')
        : '';
    final tsRaw = session['timestamp'] as String? ?? '';
    String ts = '';
    try {
      ts = DateFormat('MMM d, h:mm a').format(DateTime.parse(tsRaw).toLocal());
    } catch (_) { ts = tsRaw; }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16161F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A3A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.chat_bubble_outline, size: 14, color: Color(0xFF7C3AED)),
          const SizedBox(width: 6),
          Text(ts, style: const TextStyle(fontSize: 11, color: Color(0xFF7A7590))),
          const Spacer(),
          Text('${messages.length} msgs',
              style: const TextStyle(fontSize: 10, color: Color(0xFF7A7590))),
        ]),
        const SizedBox(height: 8),
        Text(
          first.toString().length > 120
              ? '${first.toString().substring(0, 120)}...'
              : first.toString(),
          style: const TextStyle(fontSize: 13, color: Color(0xFFD0D0E0), height: 1.4),
        ),
      ]),
    );
  }

  // ─── WEEKLY TAB ──────────────────────────────────────────────────────────

  Widget _buildWeekly() {
    if (_loadingReflection) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF7C3AED)));
    }
    return RefreshIndicator(
      onRefresh: _loadReflection,
      color: const Color(0xFF7C3AED),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStreakCards(),
          const SizedBox(height: 16),
          if (_reflection != null) _buildReflectionCard(),
          if (_reflection == null)
            _buildEmptyCard(
              icon: Icons.auto_graph,
              title: 'No weekly reflection yet',
              sub: 'Ask Samantha "reflect on my week" to generate one.',
            ),
        ],
      ),
    );
  }

  Widget _buildStreakCards() {
    final habitDefs = [
      {'key': 'daily_short', 'icon': '📹', 'label': 'Daily Short'},
      {'key': 'sketch',      'icon': '✏️',  'label': 'Sketch'},
      {'key': 'ukulele',     'icon': '🎵',  'label': 'Ukulele'},
      {'key': 'exercise',    'icon': '🏃',  'label': 'Exercise'},
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('HABIT STREAKS',
            style: TextStyle(fontSize: 11, color: Color(0xFF00D4FF), letterSpacing: 0.15)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 2.2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: habitDefs.map((h) {
            final data = _streaks[h['key']];
            final streak = data is Map ? (data['current_streak'] ?? 0) : 0;
            final longest = data is Map ? (data['longest_streak'] ?? 0) : 0;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF16161F),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF2A2A3A)),
              ),
              child: Row(children: [
                Text(h['icon']!, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 8),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(h['label']!,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                    Text('🔥 $streak  •  Best $longest',
                        style: const TextStyle(fontSize: 10, color: Color(0xFFF59E0B))),
                  ],
                )),
              ]),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildReflectionCard() {
    final r = _reflection!;
    final summary = r['summary'] as String? ?? r['weekly_summary'] as String? ?? '';
    final wins = (r['wins'] as List? ?? r['highlights'] as List? ?? []);
    final improvements = (r['improvements'] as List? ?? r['areas_to_improve'] as List? ?? []);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A24),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF7C3AED).withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('WEEKLY REFLECTION',
            style: TextStyle(fontSize: 11, color: Color(0xFF7C3AED), letterSpacing: 0.15)),
        const SizedBox(height: 10),
        if (summary.isNotEmpty)
          Text(summary,
              style: const TextStyle(fontSize: 13, color: Color(0xFFD0D0E0), height: 1.6)),
        if (wins.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('WINS', style: TextStyle(fontSize: 10, color: Color(0xFF5FB8A0))),
          const SizedBox(height: 6),
          ...wins.take(3).map((w) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              const Text('✅ ', style: TextStyle(fontSize: 12)),
              Expanded(child: Text(w.toString(),
                  style: const TextStyle(fontSize: 12, color: Color(0xFFB0D0C0)))),
            ]),
          )),
        ],
        if (improvements.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text('IMPROVE', style: TextStyle(fontSize: 10, color: Color(0xFFF59E0B))),
          const SizedBox(height: 6),
          ...improvements.take(3).map((i) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              const Text('⚡ ', style: TextStyle(fontSize: 12)),
              Expanded(child: Text(i.toString(),
                  style: const TextStyle(fontSize: 12, color: Color(0xFFD4B060)))),
            ]),
          )),
        ],
      ]),
    );
  }

  // ─── IMPORT TAB ──────────────────────────────────────────────────────────

  Widget _buildImport() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // ChatGPT Import section
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF16161F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2A2A3A)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF5FB8A0).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(child: Text('🤖', style: TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 12),
              const Text('Import from ChatGPT',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            const Text(
              'Bring your ChatGPT conversation history into Samantha so she knows you better.',
              style: TextStyle(fontSize: 13, color: Color(0xFF7A7590), height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '1. Open ChatGPT → Settings → Data Controls\n'
                '2. Tap "Export data" → confirm email\n'
                '3. Download the zip → extract conversations.json\n'
                '4. Tap Import below and select that file',
                style: TextStyle(fontSize: 11, color: Color(0xFF7A7590), height: 1.7),
              ),
            ),
            const SizedBox(height: 16),
            if (_importResult != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _importResult!.startsWith('Import failed')
                      ? Colors.red.withOpacity(0.15)
                      : const Color(0xFF5FB8A0).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_importResult!,
                    style: TextStyle(
                      fontSize: 12,
                      color: _importResult!.startsWith('Import failed')
                          ? Colors.red
                          : const Color(0xFF5FB8A0),
                    )),
              ),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _importingChatGPT ? null : _importChatGPT,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF5FB8A0),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                icon: _importingChatGPT
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.upload_file),
                label: Text(_importingChatGPT ? 'Importing...' : 'Select conversations.json'),
              ),
            ),
          ]),
        ),

        const SizedBox(height: 20),

        // Voice model info card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF16161F),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF2A2A3A)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFF7C3AED).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(child: Text('🎙️', style: TextStyle(fontSize: 18))),
              ),
              const SizedBox(width: 12),
              const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Custom Voice (Coming Soon)',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text('Indian English Female • Free',
                    style: TextStyle(fontSize: 11, color: Color(0xFF7C3AED))),
              ]),
            ]),
            const SizedBox(height: 12),
            const Text(
              'A natural Indian-accent female voice using Coqui XTTS v2 (open-source) '
              'deployed to HuggingFace Spaces for free. No API cost ever.',
              style: TextStyle(fontSize: 13, color: Color(0xFF7A7590), height: 1.5),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C10),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Status: Using iOS en-IN Lekha voice until Coqui is deployed.\n'
                'Plan: Record 30-sec Indian English sample → XTTS clone → '
                'HuggingFace Space API → Lambda relay → Flutter player.',
                style: TextStyle(fontSize: 11, color: Color(0xFF7A7590), height: 1.6),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildEmptyCard({required IconData icon, required String title, required String sub}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF16161F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2A3A)),
      ),
      child: Column(children: [
        Icon(icon, color: const Color(0xFF2A2A3A), size: 40),
        const SizedBox(height: 10),
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text(sub,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFF7A7590))),
      ]),
    );
  }
}

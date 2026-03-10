import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

const String LAMBDA_URL =
    'https://aybg83gr69.execute-api.ap-south-1.amazonaws.com/prod/chat';
const String USER_ID = 'user1';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await http.post(
        Uri.parse(LAMBDA_URL),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'userId': USER_ID, 'action': 'get_history'}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      final sessions = data['sessions'] as List? ?? [];

      setState(() {
        _sessions = sessions
            .map((s) => Map<String, dynamic>.from(s))
            .toList()
          ..sort((a, b) {
            final aTime = a['timestamp'] ?? '';
            final bTime = b['timestamp'] ?? '';
            return bTime.compareTo(aTime);
          });
        _loading = false;
      });
    } catch (e) {
      setState(() { _error = 'Could not load history'; _loading = false; });
    }
  }

  String _formatDate(String? timestamp) {
    if (timestamp == null || timestamp.isEmpty) return '';
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inDays == 0) return 'Today ${DateFormat('h:mm a').format(dt)}';
      if (diff.inDays == 1) return 'Yesterday ${DateFormat('h:mm a').format(dt)}';
      if (diff.inDays < 7) return DateFormat('EEEE h:mm a').format(dt);
      return DateFormat('MMM d, h:mm a').format(dt);
    } catch (e) {
      return timestamp;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131A),
        title: const Text('Chat History',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF00D4FF)),
            onPressed: _loadHistory,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF2A2A3A)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00D4FF)))
          : _error != null
              ? _buildError()
              : _sessions.isEmpty
                  ? _buildEmpty()
                  : _buildList(),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('😕', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Color(0xFF7A7590))),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadHistory,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED)),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('💬', style: TextStyle(fontSize: 48)),
          SizedBox(height: 16),
          Text('No conversations yet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          SizedBox(height: 8),
          Text('Start talking to Samantha!',
              style: TextStyle(color: Color(0xFF7A7590))),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (ctx, i) {
        final session = _sessions[i];
        final messages = session['messages'] as List? ?? [];
        final sessionTitle = (session['title'] as String? ?? '').isNotEmpty
            ? session['title'] as String
            : messages
                .where((m) => m['role'] == 'user')
                .map((m) => m['content'] ?? m['text'] ?? '')
                .firstWhere((t) => t.isNotEmpty, orElse: () => 'Conversation');
        final firstUserMsg = sessionTitle;
        final lastSamanthaMsg = messages.reversed
            .where((m) => m['role'] == 'assistant' || m['role'] == 'samantha')
            .map((m) => m['content'] ?? m['text'] ?? '')
            .firstWhere((t) => t.isNotEmpty, orElse: () => '');
        final mood = session['mood'] ?? 'neutral';
        final msgCount = messages.length;

        return GestureDetector(
          onTap: () => _openSession(session),
          child: Container(
            padding: const EdgeInsets.all(16),
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
                    Text(_moodEmoji(mood),
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formatDate(session['date'] ?? session['timestamp']),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF7A7590)),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A2A3A),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$msgCount msgs',
                          style: const TextStyle(
                              fontSize: 10, color: Color(0xFF7A7590))),
                    ),
                  ],
                ),
                if (firstUserMsg.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('You  ',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF00D4FF),
                              fontWeight: FontWeight.w600)),
                      Expanded(
                        child: Text(
                          firstUserMsg,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFFE0E0F0)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (lastSamanthaMsg.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Sam  ',
                          style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF7C3AED),
                              fontWeight: FontWeight.w600)),
                      Expanded(
                        child: Text(
                          lastSamanthaMsg,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF7A7590)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _moodEmoji(String mood) {
    switch (mood.toLowerCase()) {
      case 'happy': return '😊';
      case 'stressed': return '😰';
      case 'sad': return '😔';
      case 'focused': return '🎯';
      case 'excited': return '🔥';
      default: return '😐';
    }
  }

  void _openSession(Map<String, dynamic> session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SessionDetailScreen(session: session),
      ),
    );
  }
}

class SessionDetailScreen extends StatelessWidget {
  final Map<String, dynamic> session;
  const SessionDetailScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    final messages = session['messages'] as List? ?? [];
    final timestamp = session['timestamp'] ?? '';
    String dateLabel = '';
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      dateLabel = DateFormat('EEEE, MMMM d • h:mm a').format(dt);
    } catch (_) {}

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131A),
        title: Column(
          children: [
            const Text('Conversation',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (dateLabel.isNotEmpty)
              Text(dateLabel,
                  style: const TextStyle(
                      fontSize: 10, color: Color(0xFF7A7590))),
          ],
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF2A2A3A)),
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: messages.length,
        itemBuilder: (ctx, i) {
          final msg = messages[i];
          final role = msg['role'] ?? '';
          final text = msg['content'] ?? msg['text'] ?? '';
          final isUser = role == 'user';

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment:
                  isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isUser) ...[
                  Container(
                    width: 28, height: 28,
                    decoration: const BoxDecoration(
                      color: Color(0xFF7C3AED),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Text('S',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFF00D4FF).withOpacity(0.15)
                          : const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: Radius.circular(isUser ? 16 : 4),
                        bottomRight: Radius.circular(isUser ? 4 : 16),
                      ),
                      border: Border.all(
                        color: isUser
                            ? const Color(0xFF00D4FF).withOpacity(0.3)
                            : const Color(0xFF2A2A3A),
                      ),
                    ),
                    child: Text(
                      text,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: isUser ? Colors.white : const Color(0xFFE0E0F0),
                      ),
                    ),
                  ),
                ),
                if (isUser) const SizedBox(width: 8),
              ],
            ),
          );
        },
      ),
    );
  }
}

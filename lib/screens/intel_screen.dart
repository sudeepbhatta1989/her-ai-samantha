import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

// ─── Constants ───────────────────────────────────────────────────────────────
const String _apiUrl =
    'https://aybg83gr69.execute-api.ap-south-1.amazonaws.com/prod/chat';
const String _userId = 'user1';

const Color _bg       = Color(0xFF06060F);
const Color _surface  = Color(0xFF0F0F1E);
const Color _card     = Color(0xFF13131F);
const Color _border   = Color(0xFF1E1E30);
const Color _purple   = Color(0xFF7C3AED);
const Color _cyan     = Color(0xFF00D4FF);
const Color _gold     = Color(0xFFFFD700);
const Color _green    = Color(0xFF00FF88);
const Color _text     = Color(0xFFE8E8F0);
const Color _sub      = Color(0xFF6B6B8A);

// ─── Models ──────────────────────────────────────────────────────────────────
class IntelItem {
  final String id;
  final String type;      // research | content | strategy | memory
  final String title;
  final String subtitle;
  final String preview;
  final String fullText;
  final String date;
  final Color typeColor;
  final IconData typeIcon;

  IntelItem({
    required this.id,
    required this.type,
    required this.title,
    required this.subtitle,
    required this.preview,
    required this.fullText,
    required this.date,
    required this.typeColor,
    required this.typeIcon,
  });
}

// ─── Screen ──────────────────────────────────────────────────────────────────
class IntelScreen extends StatefulWidget {
  const IntelScreen({Key? key}) : super(key: key);

  @override
  State<IntelScreen> createState() => _IntelScreenState();
}

class _IntelScreenState extends State<IntelScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // Data
  List<IntelItem> _research   = [];
  List<IntelItem> _content    = [];
  List<IntelItem> _strategy   = [];
  List<IntelItem> _memories   = [];
  List<IntelItem> _searchResults = [];

  bool _loadingResearch  = true;
  bool _loadingContent   = true;
  bool _loadingStrategy  = true;
  bool _loadingMemories  = true;
  bool _searching        = false;
  bool _searchMode       = false;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(_pulseCtrl);
    _loadAll();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ─── API calls ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> _call(Map<String, dynamic> payload) async {
    try {
      final resp = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(resp.body);
      if (decoded is Map && decoded.containsKey('body')) {
        return jsonDecode(decoded['body']) as Map<String, dynamic>;
      }
      return decoded as Map<String, dynamic>;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  void _loadAll() {
    _loadResearch();
    _loadContent();
    _loadStrategy();
    _loadMemories();
  }

  Future<void> _loadResearch() async {
    setState(() => _loadingResearch = true);
    final r = await _call({'userId': _userId, 'action': 'get_research_reports'});
    final list = <IntelItem>[];
    for (final item in (r['reports'] as List? ?? [])) {
      list.add(IntelItem(
        id: item['id'] ?? '',
        type: 'research',
        title: _shorten(item['topic'] ?? item['query'] ?? 'Research', 60),
        subtitle: item['date'] ?? '',
        preview: _shorten(item['report'] ?? '', 160),
        fullText: item['report'] ?? '',
        date: item['date'] ?? '',
        typeColor: _cyan,
        typeIcon: Icons.science_outlined,
      ));
    }
    if (mounted) setState(() { _research = list; _loadingResearch = false; });
  }

  Future<void> _loadContent() async {
    setState(() => _loadingContent = true);
    final r = await _call({'userId': _userId, 'action': 'get_content_scripts'});
    final list = <IntelItem>[];
    for (final item in (r['scripts'] as List? ?? [])) {
      final ctype = item['content_type'] ?? item['type'] ?? 'Script';
      final topic = item['topic'] ?? item['id'] ?? '';
      list.add(IntelItem(
        id: item['id'] ?? '',
        type: 'content',
        title: _shorten(topic, 60),
        subtitle: _contentTypeLabel(ctype),
        preview: _shorten(item['script'] ?? item['content'] ?? '', 160),
        fullText: item['script'] ?? item['content'] ?? '',
        date: item['date'] ?? item['created_at'] ?? '',
        typeColor: _purple,
        typeIcon: Icons.movie_creation_outlined,
      ));
    }
    if (mounted) setState(() { _content = list; _loadingContent = false; });
  }

  Future<void> _loadStrategy() async {
    setState(() => _loadingStrategy = true);
    final r = await _call({'userId': _userId, 'action': 'get_strategy_reports'});
    final list = <IntelItem>[];
    for (final item in (r['reports'] as List? ?? [])) {
      list.add(IntelItem(
        id: item['id'] ?? '',
        type: 'strategy',
        title: item['month_name'] ?? item['id'] ?? 'Strategy',
        subtitle: '${(item['domains_analyzed'] as List? ?? []).length} domains analyzed',
        preview: _shorten(item['report'] ?? '', 160),
        fullText: item['report'] ?? '',
        date: item['month'] ?? '',
        typeColor: _gold,
        typeIcon: Icons.insights_outlined,
      ));
    }
    if (mounted) setState(() { _strategy = list; _loadingStrategy = false; });
  }

  Future<void> _loadMemories() async {
    setState(() => _loadingMemories = true);
    final r = await _call({'userId': _userId, 'action': 'get_agent_logs'});
    // Use agent logs as proxy for memories display
    final list = <IntelItem>[];
    for (final item in (r['logs'] as List? ?? []).take(30)) {
      final agent = item['agent'] ?? 'agent';
      list.add(IntelItem(
        id: item['id'] ?? '',
        type: 'memory',
        title: _shorten(item['action'] ?? item['summary'] ?? 'Agent activity', 60),
        subtitle: _agentLabel(agent),
        preview: _shorten(item['details'] ?? item['result'] ?? '', 160),
        fullText: item['details'] ?? item['result'] ?? jsonEncode(item),
        date: item['timestamp'] ?? item['date'] ?? '',
        typeColor: _green,
        typeIcon: Icons.memory_outlined,
      ));
    }
    if (mounted) setState(() { _memories = list; _loadingMemories = false; });
  }

  Future<void> _doSearch(String query) async {
    if (query.trim().isEmpty) {
      setState(() { _searchMode = false; _searchResults = []; });
      return;
    }
    setState(() { _searching = true; _searchMode = true; });
    final r = await _call({
      'userId': _userId,
      'action': 'semantic_search',
      'query': query,
      'search_type': 'all',
    });

    final list = <IntelItem>[];
    for (final item in (r['content'] as List? ?? [])) {
      final typeStr = item['type'] ?? 'content';
      list.add(IntelItem(
        id: item['id'] ?? '',
        type: typeStr,
        title: _shorten(item['title'] ?? '', 60),
        subtitle: typeStr.toUpperCase(),
        preview: _shorten(item['preview'] ?? '', 160),
        fullText: item['preview'] ?? '',
        date: item['date'] ?? '',
        typeColor: _typeColor(typeStr),
        typeIcon: _typeIcon(typeStr),
      ));
    }
    for (final item in (r['memories'] as List? ?? [])) {
      list.add(IntelItem(
        id: item['id'] ?? '',
        type: 'memory',
        title: _shorten(item['text'] ?? '', 60),
        subtitle: item['category'] ?? 'memory',
        preview: _shorten(item['text'] ?? '', 160),
        fullText: item['text'] ?? '',
        date: item['date'] ?? '',
        typeColor: _green,
        typeIcon: Icons.memory_outlined,
      ));
    }
    if (mounted) setState(() { _searchResults = list; _searching = false; });
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────
  String _shorten(String s, int max) =>
      s.length > max ? '${s.substring(0, max)}…' : s;

  String _contentTypeLabel(String t) {
    const map = {
      'phokat_short': 'Phokat ka Gyan — Reel',
      'corporate_kurukshetra': 'Corporate Kurukshetra',
      'youtube': 'YouTube',
      'instagram': 'Instagram',
      'debate': 'Debate Script',
    };
    return map[t] ?? t;
  }

  String _agentLabel(String a) {
    const map = {
      'research_agent': 'Research',
      'content_agent': 'Content',
      'coding_agent': 'Code',
      'planner_agent': 'Planner',
      'reflection_agent': 'Reflection',
    };
    return map[a] ?? a;
  }

  Color _typeColor(String t) {
    switch (t) {
      case 'research': return _cyan;
      case 'content':  return _purple;
      case 'strategy': return _gold;
      default:         return _green;
    }
  }

  IconData _typeIcon(String t) {
    switch (t) {
      case 'research': return Icons.science_outlined;
      case 'content':  return Icons.movie_creation_outlined;
      case 'strategy': return Icons.insights_outlined;
      default:         return Icons.memory_outlined;
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(children: [
          _buildHeader(),
          _buildSearchBar(),
          if (!_searchMode) _buildTabBar(),
          Expanded(
            child: _searchMode
                ? _buildSearchResults()
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildList(_research,  _loadingResearch,  'No research reports yet.\nAsk Samantha to research any topic.'),
                      _buildList(_content,   _loadingContent,   'No scripts yet.\nAsk Samantha to create content.'),
                      _buildList(_strategy,  _loadingStrategy,  'No strategy reports yet.\nRuns on the 1st of each month.'),
                      _buildList(_memories,  _loadingMemories,  'No activity logs yet.'),
                    ],
                  ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(children: [
        // Pulsing orb
        AnimatedBuilder(
          animation: _pulseAnim,
          builder: (_, __) => Container(
            width: 10, height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _cyan.withOpacity(_pulseAnim.value),
              boxShadow: [BoxShadow(color: _cyan.withOpacity(0.6), blurRadius: 8)],
            ),
          ),
        ),
        const SizedBox(width: 10),
        const Text('INTEL', style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          letterSpacing: 4,
          color: _cyan,
          fontWeight: FontWeight.w600,
        )),
        const Spacer(),
        Text('SAMANTHA // MEMORY CORE',
          style: TextStyle(fontFamily: 'monospace', fontSize: 10,
              letterSpacing: 2, color: _sub)),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: _loadAll,
          child: Icon(Icons.refresh, color: _sub, size: 18),
        ),
      ]),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _searchFocus.hasFocus ? _purple.withOpacity(0.6) : _border,
          ),
        ),
        child: Row(children: [
          const SizedBox(width: 14),
          Icon(Icons.search, color: _sub, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              style: const TextStyle(color: _text, fontSize: 14, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: 'Semantic search across all intel…',
                hintStyle: TextStyle(color: Color(0xFF3A3A5C), fontSize: 14),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
              onSubmitted: _doSearch,
              onChanged: (v) {
                if (v.isEmpty) setState(() { _searchMode = false; _searchResults = []; });
              },
            ),
          ),
          if (_searchMode)
            GestureDetector(
              onTap: () {
                _searchCtrl.clear();
                setState(() { _searchMode = false; _searchResults = []; });
              },
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(Icons.close, color: _sub, size: 16),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _purple.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _purple.withOpacity(0.3)),
                ),
                child: Text('AI', style: TextStyle(
                  fontFamily: 'monospace', fontSize: 10,
                  color: _purple, letterSpacing: 2,
                )),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _buildTabBar() {
    final tabs = [
      {'label': 'RESEARCH', 'color': _cyan,   'count': _research.length},
      {'label': 'CONTENT',  'color': _purple,  'count': _content.length},
      {'label': 'STRATEGY', 'color': _gold,    'count': _strategy.length},
      {'label': 'ACTIVITY', 'color': _green,   'count': _memories.length},
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        indicatorColor: Colors.transparent,
        dividerColor: Colors.transparent,
        tabs: tabs.asMap().entries.map((entry) {
          final i = entry.key;
          final tab = entry.value;
          return AnimatedBuilder(
            animation: _tabController.animation!,
            builder: (_, __) {
              final selected = _tabController.index == i;
              final color = tab['color'] as Color;
              return Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: selected ? color.withOpacity(0.15) : _card,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? color.withOpacity(0.5) : _border,
                  ),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(tab['label'] as String, style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    letterSpacing: 1.5,
                    color: selected ? color : _sub,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  )),
                  if ((tab['count'] as int) > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: selected ? color.withOpacity(0.3) : _border,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${tab['count']}', style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9,
                        color: selected ? color : _sub,
                      )),
                    ),
                  ],
                ]),
              );
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildList(List<IntelItem> items, bool loading, String emptyMsg) {
    if (loading) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 1.5, color: _cyan.withOpacity(0.6),
            ),
          ),
          const SizedBox(height: 12),
          Text('LOADING INTEL…', style: TextStyle(
            fontFamily: 'monospace', fontSize: 10, letterSpacing: 3, color: _sub,
          )),
        ]),
      );
    }
    if (items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.inbox_outlined, color: _sub, size: 32),
          const SizedBox(height: 12),
          Text(emptyMsg, textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'monospace', fontSize: 12,
                color: _sub, height: 1.8)),
        ]),
      );
    }
    return RefreshIndicator(
      color: _cyan,
      backgroundColor: _card,
      onRefresh: _loadAll,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: items.length,
        itemBuilder: (ctx, i) => _buildCard(items[i]),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searching) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(strokeWidth: 1.5, color: _purple.withOpacity(0.6)),
          ),
          const SizedBox(height: 12),
          Text('SEARCHING SEMANTIC MEMORY…',
            style: TextStyle(fontFamily: 'monospace', fontSize: 10, letterSpacing: 2, color: _sub)),
        ]),
      );
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off_outlined, color: _sub, size: 32),
          const SizedBox(height: 12),
          Text('No results found', style: TextStyle(
            fontFamily: 'monospace', fontSize: 12, color: _sub)),
        ]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
          child: Text('${_searchResults.length} RESULTS — "${_searchCtrl.text}"',
            style: TextStyle(fontFamily: 'monospace', fontSize: 10,
                letterSpacing: 2, color: _sub)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: _searchResults.length,
            itemBuilder: (ctx, i) => _buildCard(_searchResults[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(IntelItem item) {
    return GestureDetector(
      onTap: () => _openDetail(item),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Top bar with type indicator
          Container(
            decoration: BoxDecoration(
              color: item.typeColor.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              border: Border(bottom: BorderSide(color: item.typeColor.withOpacity(0.2))),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(children: [
              Icon(item.typeIcon, color: item.typeColor, size: 13),
              const SizedBox(width: 7),
              Text(item.subtitle.toUpperCase(), style: TextStyle(
                fontFamily: 'monospace', fontSize: 9,
                letterSpacing: 2, color: item.typeColor,
              )),
              const Spacer(),
              if (item.date.isNotEmpty)
                Text(_formatDate(item.date), style: TextStyle(
                  fontFamily: 'monospace', fontSize: 9, color: _sub,
                )),
            ]),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.title, style: const TextStyle(
                color: _text, fontSize: 14, fontWeight: FontWeight.w500, height: 1.4,
              )),
              if (item.preview.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(item.preview, style: TextStyle(
                  color: _sub, fontSize: 12, height: 1.6,
                )),
              ],
              const SizedBox(height: 10),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: item.typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: item.typeColor.withOpacity(0.25)),
                  ),
                  child: Text('VIEW FULL', style: TextStyle(
                    fontFamily: 'monospace', fontSize: 9,
                    letterSpacing: 1.5, color: item.typeColor,
                  )),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  String _formatDate(String d) {
    if (d.isEmpty) return '';
    try {
      if (d.length == 10) { // YYYY-MM-DD
        final parts = d.split('-');
        final months = ['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        return '${months[int.parse(parts[1])]} ${parts[2]}, ${parts[0]}';
      }
      if (d.length == 7) return d; // YYYY-MM
    } catch (_) {}
    return d.substring(0, d.length < 10 ? d.length : 10);
  }

  void _openDetail(IntelItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DetailSheet(item: item),
    );
  }
}

// ─── Detail Bottom Sheet ──────────────────────────────────────────────────────
class _DetailSheet extends StatelessWidget {
  final IntelItem item;
  const _DetailSheet({required this.item});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border.all(color: item.typeColor.withOpacity(0.3)),
        ),
        child: Column(children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 36, height: 3,
              decoration: BoxDecoration(
                color: _border, borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Container(
            margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: item.typeColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: item.typeColor.withOpacity(0.25)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(item.typeIcon, color: item.typeColor, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.subtitle.toUpperCase(), style: TextStyle(
                    fontFamily: 'monospace', fontSize: 9,
                    letterSpacing: 2, color: item.typeColor,
                  )),
                  const SizedBox(height: 4),
                  Text(item.title, style: const TextStyle(
                    color: _text, fontSize: 15, fontWeight: FontWeight.w600, height: 1.4,
                  )),
                  if (item.date.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(item.date, style: TextStyle(
                      fontFamily: 'monospace', fontSize: 10, color: _sub,
                    )),
                  ],
                ]),
              ),
            ]),
          ),
          // Divider
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            height: 1,
            color: _border,
          ),
          // Full text
          Expanded(
            child: SingleChildScrollView(
              controller: scrollCtrl,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: item.fullText.isEmpty
                  ? Center(
                      child: Text('No content available', style: TextStyle(
                        fontFamily: 'monospace', fontSize: 12, color: _sub,
                      )),
                    )
                  : Text(item.fullText, style: const TextStyle(
                      color: _text, fontSize: 13, height: 1.8,
                    )),
            ),
          ),
        ]),
      ),
    );
  }
}

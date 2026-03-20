// lib/screens/schedule_screen.dart
// Drop into: app/lib/screens/schedule_screen.dart
// Add to navigation: ScheduleScreen()

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/schedule_event.dart';
import '../providers/schedule_provider.dart';
import '../services/schedule_service.dart';
import '../widgets/schedule/event_tile.dart';
import '../widgets/schedule/conflict_card.dart';
import '../widgets/schedule/briefing_banner.dart';
import '../widgets/schedule/add_event_sheet.dart';
import '../widgets/schedule/week_strip.dart';

// ── Samantha brand tokens ─────────────────────────────────────────────────
const kBg        = Color(0xFF0A0A1A);
const kSurface   = Color(0xFF12122A);
const kCard      = Color(0xFF1A1A35);
const kAccent    = Color(0xFF7C5CFC);
const kAccentLt  = Color(0xFF9B7FFF);
const kText      = Color(0xFFEEEEFF);
const kSubtext   = Color(0xFF9090B0);
const kDanger    = Color(0xFFFF4B6E);
const kSuccess   = Color(0xFF4BFF91);
const kGoogleRed = Color(0xFFEA4335);
const kAppleGray = Color(0xFF8E8E93);

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});
  @override State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _chatCtrl = TextEditingController();
  final List<_ChatMsg> _chatHistory = [];
  bool _chatLoading = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _tabs.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ScheduleProvider>().loadBriefing();
    });
  }

  @override
  void dispose() { _tabs.dispose(); _chatCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ScheduleProvider()..loadBriefing(),
      child: Consumer<ScheduleProvider>(
        builder: (ctx, prov, _) => Scaffold(
          backgroundColor: kBg,
          body: SafeArea(child: Column(children: [
            _Header(prov: prov, onSync: prov.syncCalendars),
            WeekStrip(selected: prov.selectedDate, onSelect: prov.selectDate),
            _Tabs(controller: _tabs),
            Expanded(child: TabBarView(controller: _tabs, children: [
              _DayView(prov: prov),
              _WeekView(prov: prov),
              _AIChatView(
                history: _chatHistory,
                loading: _chatLoading,
                controller: _chatCtrl,
                onSend: (t) => _sendChat(ctx, t, prov),
              ),
            ])),
          ])),
          floatingActionButton: _tabs.index != 2
              ? FloatingActionButton(
                  backgroundColor: kAccent,
                  onPressed: () => _showAdd(ctx, prov),
                  child: const Icon(Icons.add, color: Colors.white),
                )
              : null,
        ),
      ),
    );
  }

  // ── CHAT ─────────────────────────────────────────────────────────────────

  Future<void> _sendChat(BuildContext ctx, String text, ScheduleProvider prov) async {
    if (text.trim().isEmpty) return;
    setState(() {
      _chatHistory.add(_ChatMsg(text: text, isUser: true));
      _chatLoading = true;
    });
    _chatCtrl.clear();

    final result = await ScheduleService.instance.parseNaturalLanguage(text);
    final action = result['action'] as String? ?? 'unknown';
    String reply;

    if (action == 'create' && result['event'] != null) {
      reply = "Got it — I'll add that to your schedule. Tap ✅ to confirm.";
    } else if (action == 'query') {
      final conflicts = prov.briefing?.conflicts ?? [];
      reply = conflicts.isEmpty
          ? 'Your schedule looks clear — no conflicts today! ✅'
          : '⚠️ I found ${conflicts.length} conflict${conflicts.length > 1 ? 's' : ''} today. Check the Day tab to resolve them.';
    } else if (action == 'reschedule') {
      reply = "I can help reschedule that. Switch to Day view to see the conflict suggestions.";
    } else {
      reply = "I can add events, check conflicts, or reschedule things. Try: \"Add team meeting tomorrow at 10am\" or \"Any conflicts this week?\"";
    }

    setState(() {
      _chatHistory.add(_ChatMsg(text: reply, isUser: false));
      _chatLoading = false;
    });
  }

  // ── MODALS ────────────────────────────────────────────────────────────────

  void _showAdd(BuildContext ctx, ScheduleProvider prov) {
    showModalBottomSheet(
      context: ctx, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => AddEventSheet(
        initialDate: prov.selectedDate,
        onSave: (e) async { await prov.createEvent(e); _snack(ctx, '✅ Event added'); },
      ),
    );
  }

  void _snack(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: kText)),
      backgroundColor: kCard,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// HEADER
// ═══════════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final ScheduleProvider prov;
  final VoidCallback onSync;
  const _Header({required this.prov, required this.onSync});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(children: [
        Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [kAccent, kAccentLt]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Schedule', style: TextStyle(color: kText, fontSize: 20, fontWeight: FontWeight.w700)),
          Text(DateFormat('EEE, d MMM').format(prov.selectedDate),
              style: const TextStyle(color: kSubtext, fontSize: 12)),
        ]),
        const Spacer(),
        // Sync button
        GestureDetector(
          onTap: prov.syncing ? null : onSync,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: kSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kAccent.withOpacity(0.3)),
            ),
            child: Row(children: [
              prov.syncing
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kAccent))
                  : const Icon(Icons.sync, color: kAccent, size: 14),
              const SizedBox(width: 6),
              Text(prov.syncing ? 'Syncing...' : 'Sync',
                  style: const TextStyle(color: kAccent, fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        // Conflict badge
        if ((prov.briefing?.conflicts.length ?? 0) > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: kDanger.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: kDanger.withOpacity(0.35)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: kDanger, size: 13),
              const SizedBox(width: 4),
              Text('${prov.briefing!.conflicts.length}',
                  style: const TextStyle(color: kDanger, fontSize: 12, fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB BAR
// ═══════════════════════════════════════════════════════════════════════════

class _Tabs extends StatelessWidget {
  final TabController controller;
  const _Tabs({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(color: kSurface, borderRadius: BorderRadius.circular(12)),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(10)),
        labelColor: Colors.white,
        unselectedLabelColor: kSubtext,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        tabs: const [Tab(text: 'Day'), Tab(text: 'Week'), Tab(text: '✨ Ask')],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// DAY VIEW
// ═══════════════════════════════════════════════════════════════════════════

class _DayView extends StatelessWidget {
  final ScheduleProvider prov;
  const _DayView({required this.prov});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ScheduleEvent>>(
      stream: ScheduleService.instance.watchDay(prov.selectedDate),
      builder: (ctx, snap) {
        final events = snap.data ?? [];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            // Sync status pill
            if (prov.syncStatus != null)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: kSuccess.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kSuccess.withOpacity(0.3)),
                ),
                child: Text(prov.syncStatus!, style: const TextStyle(color: kSuccess, fontSize: 13)),
              ),

            // AI Briefing
            if (prov.loadingBriefing)
              _LoadingBriefing()
            else if (prov.briefing != null)
              BriefingBanner(briefing: prov.briefing!),
            const SizedBox(height: 14),

            // Calendar source legend
            if (events.any((e) => e.source != EventSource.samantha))
              _CalendarLegend(events: events),

            // Conflict cards
            ...?prov.briefing?.conflicts.map((c) => ConflictCard(
              conflict: c,
              onAccept: (s) async {
                await prov.acceptReschedule(s);
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text('✅ Rescheduled: ${s.eventTitle}',
                      style: const TextStyle(color: kText)),
                  backgroundColor: kCard, behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ));
              },
            )),
            if ((prov.briefing?.conflicts.length ?? 0) > 0) const SizedBox(height: 8),

            // Events
            if (events.isEmpty)
              _EmptyDay()
            else
              ...events.map((e) {
                final hasConflict = events.any((other) =>
                    other.id != e.id && e.overlapsWith(other));
                return EventTile(
                  event: e,
                  hasConflict: hasConflict,
                  onDelete: () => prov.deleteEvent(e.id),
                  onEdit: () => showModalBottomSheet(
                    context: ctx, isScrollControlled: true, backgroundColor: Colors.transparent,
                    builder: (_) => AddEventSheet(
                      initialDate: prov.selectedDate, existingEvent: e,
                      onSave: (updated) => prov.updateEvent(updated),
                    ),
                  ),
                );
              }),
          ],
        );
      },
    );
  }
}

class _LoadingBriefing extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kCard, borderRadius: BorderRadius.circular(14),
      border: Border.all(color: kAccent.withOpacity(0.2)),
    ),
    child: Row(children: [
      SizedBox(width: 18, height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)),
      const SizedBox(width: 12),
      const Text('Samantha is reviewing your day...', style: TextStyle(color: kSubtext, fontSize: 13)),
    ]),
  );
}

class _CalendarLegend extends StatelessWidget {
  final List<ScheduleEvent> events;
  const _CalendarLegend({required this.events});

  @override
  Widget build(BuildContext context) {
    final hasGoogle = events.any((e) => e.source == EventSource.googleCalendar);
    final hasApple = events.any((e) => e.source == EventSource.appleCalendar);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        if (hasGoogle) ...[
          const Icon(Icons.circle, color: kGoogleRed, size: 8),
          const SizedBox(width: 4),
          const Text('Google', style: TextStyle(color: kSubtext, fontSize: 11)),
          const SizedBox(width: 12),
        ],
        if (hasApple) ...[
          const Icon(Icons.circle, color: kAppleGray, size: 8),
          const SizedBox(width: 4),
          const Text('Apple', style: TextStyle(color: kSubtext, fontSize: 11)),
          const SizedBox(width: 12),
        ],
        const Icon(Icons.circle, color: kAccent, size: 8),
        const SizedBox(width: 4),
        const Text('Samantha', style: TextStyle(color: kSubtext, fontSize: 11)),
      ]),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(top: 20),
    padding: const EdgeInsets.all(32),
    decoration: BoxDecoration(
      color: kCard, borderRadius: BorderRadius.circular(20),
      border: Border.all(color: kAccent.withOpacity(0.1)),
    ),
    child: Column(children: [
      Icon(Icons.wb_sunny_outlined, color: kAccent.withOpacity(0.5), size: 44),
      const SizedBox(height: 12),
      const Text('Nothing scheduled', style: TextStyle(color: kText, fontSize: 17, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      const Text('Tap + to add an event, or Sync to pull from your calendars.',
          textAlign: TextAlign.center, style: TextStyle(color: kSubtext, fontSize: 13)),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// WEEK VIEW
// ═══════════════════════════════════════════════════════════════════════════

class _WeekView extends StatelessWidget {
  final ScheduleProvider prov;
  const _WeekView({required this.prov});

  @override
  Widget build(BuildContext context) {
    final weekStart = prov.selectedDate.subtract(
        Duration(days: prov.selectedDate.weekday - 1));
    return StreamBuilder<List<ScheduleEvent>>(
      stream: ScheduleService.instance.watchWeek(weekStart),
      builder: (ctx, snap) {
        final all = snap.data ?? [];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: List.generate(7, (i) {
            final day = weekStart.add(Duration(days: i));
            final dayEvents = all.where((e) =>
                DateFormat('yyyyMMdd').format(e.startTime) ==
                DateFormat('yyyyMMdd').format(day)).toList();
            final isToday = DateFormat('yyyyMMdd').format(day) ==
                DateFormat('yyyyMMdd').format(DateTime.now());
            return _WeekDayRow(day: day, events: dayEvents, isToday: isToday);
          }),
        );
      },
    );
  }
}

class _WeekDayRow extends StatelessWidget {
  final DateTime day;
  final List<ScheduleEvent> events;
  final bool isToday;
  const _WeekDayRow({required this.day, required this.events, required this.isToday});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: kSurface, borderRadius: BorderRadius.circular(14),
      border: isToday ? Border.all(color: kAccent.withOpacity(0.4)) : null,
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: isToday ? kAccent : kCard,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text('${day.day}', style: TextStyle(
                color: isToday ? Colors.white : kSubtext, fontSize: 14, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Text(DateFormat('EEEE').format(day), style: TextStyle(
              color: isToday ? kAccentLt : kText, fontSize: 14, fontWeight: FontWeight.w600)),
          const Spacer(),
          if (events.isNotEmpty)
            Text('${events.length}', style: const TextStyle(color: kSubtext, fontSize: 12)),
        ]),
      ),
      if (events.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          child: Text('Free', style: TextStyle(color: kSubtext.withOpacity(0.5), fontSize: 12)),
        )
      else ...[
        ...events.map((e) => Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 2),
          child: Row(children: [
            _sourceIcon(e.source),
            const SizedBox(width: 6),
            Text(DateFormat('HH:mm').format(e.startTime),
                style: const TextStyle(color: kSubtext, fontSize: 11)),
            const SizedBox(width: 8),
            Expanded(child: Text(e.title,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: kText, fontSize: 13))),
          ]),
        )),
        const SizedBox(height: 8),
      ],
    ]),
  );

  Widget _sourceIcon(EventSource s) {
    switch (s) {
      case EventSource.googleCalendar: return const Icon(Icons.circle, color: kGoogleRed, size: 7);
      case EventSource.appleCalendar: return const Icon(Icons.circle, color: kAppleGray, size: 7);
      default: return const Icon(Icons.circle, color: kAccent, size: 7);
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// AI CHAT VIEW
// ═══════════════════════════════════════════════════════════════════════════

class _ChatMsg { final String text; final bool isUser; _ChatMsg({required this.text, required this.isUser}); }

class _AIChatView extends StatelessWidget {
  final List<_ChatMsg> history;
  final bool loading;
  final TextEditingController controller;
  final Function(String) onSend;
  const _AIChatView({required this.history, required this.loading,
      required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Expanded(child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        children: [
          // Samantha intro
          _BubbleSamantha(text:
              'Hi! I can manage your schedule. Try:\n\n'
              '• "Add standup tomorrow at 10am"\n'
              '• "Block Thursday afternoon for deep work"\n'
              '• "Any conflicts today?"\n'
              '• "Move my 3pm call to after 5pm"'),
          ...history.map((m) => m.isUser
              ? _BubbleUser(text: m.text)
              : _BubbleSamantha(text: m.text)),
          if (loading)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(children: [
                SizedBox(width: 28, height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2, color: kAccent)),
              ]),
            ),
        ],
      )),
      _ChatInput(controller: controller, onSend: onSend),
    ]);
  }
}

class _BubbleSamantha extends StatelessWidget {
  final String text;
  const _BubbleSamantha({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10, right: 40),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: kCard, borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(4), topRight: Radius.circular(16),
        bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
      border: Border.all(color: kAccent.withOpacity(0.2)),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 26, height: 26,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [kAccent, kAccentLt]),
          borderRadius: BorderRadius.circular(7)),
        alignment: Alignment.center,
        child: const Text('S', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(text, style: const TextStyle(color: kText, fontSize: 13, height: 1.5))),
    ]),
  );
}

class _BubbleUser extends StatelessWidget {
  final String text;
  const _BubbleUser({required this.text});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 10, left: 40),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: kAccent.withOpacity(0.2), borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(16), topRight: Radius.circular(4),
        bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
    ),
    child: Text(text, style: const TextStyle(color: kText, fontSize: 13)),
  );
}

class _ChatInput extends StatelessWidget {
  final TextEditingController controller;
  final Function(String) onSend;
  const _ChatInput({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    decoration: BoxDecoration(
      color: kBg, border: Border(top: BorderSide(color: kAccent.withOpacity(0.1)))),
    child: Row(children: [
      Expanded(child: Container(
        decoration: BoxDecoration(
          color: kSurface, borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kAccent.withOpacity(0.3))),
        child: TextField(
          controller: controller,
          style: const TextStyle(color: kText, fontSize: 14),
          decoration: const InputDecoration(
            hintText: 'Ask Samantha about your schedule...',
            hintStyle: TextStyle(color: kSubtext, fontSize: 14),
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          onSubmitted: onSend,
        ),
      )),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => onSend(controller.text),
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [kAccent, kAccentLt]),
            borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
        ),
      ),
    ]),
  );
}

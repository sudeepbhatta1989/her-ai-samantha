// ═══════════════════════════════════════════════════════════════
// lib/widgets/schedule/conflict_card.dart
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/schedule_event.dart';

const _bg      = Color(0xFF0A0A1A);
const _card    = Color(0xFF1A1A35);
const _accent  = Color(0xFF7C5CFC);
const _text    = Color(0xFFEEEEFF);
const _subtext = Color(0xFF9090B0);
const _danger  = Color(0xFFFF4B6E);

class ConflictCard extends StatefulWidget {
  final ConflictInfo conflict;
  final Function(RescheduleSuggestion) onAccept;
  const ConflictCard({super.key, required this.conflict, required this.onAccept});
  @override State<ConflictCard> createState() => _ConflictCardState();
}

class _ConflictCardState extends State<ConflictCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.conflict;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _danger.withOpacity(0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _danger.withOpacity(0.3)),
      ),
      child: Column(children: [
        GestureDetector(
          onTap: () => setState(() => _open = !_open),
          child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: _danger, size: 17),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Schedule Conflict',
                  style: TextStyle(color: _danger, fontSize: 12, fontWeight: FontWeight.w700)),
              Text('"${c.a.title}" and "${c.b.title}" overlap by ${_dur(c.overlap)}',
                  style: const TextStyle(color: _subtext, fontSize: 11)),
            ])),
            Icon(_open ? Icons.expand_less : Icons.expand_more, color: _subtext, size: 18),
          ])),
        ),
        if (_open) ...[
          Divider(color: _danger.withOpacity(0.15), height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Samantha suggests:',
                  style: TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...c.suggestions.map((s) => _SuggestionRow(s: s, onAccept: widget.onAccept)),
            ]),
          ),
        ],
      ]),
    );
  }

  String _dur(Duration d) => d.inHours >= 1
      ? '${d.inHours}h ${d.inMinutes.remainder(60)}m'
      : '${d.inMinutes}min';
}

class _SuggestionRow extends StatelessWidget {
  final RescheduleSuggestion s;
  final Function(RescheduleSuggestion) onAccept;
  const _SuggestionRow({required this.s, required this.onAccept});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: _card, borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _accent.withOpacity(0.2))),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Move "${s.eventTitle}"',
            style: const TextStyle(color: _text, fontSize: 12, fontWeight: FontWeight.w600)),
        Text('${DateFormat("HH:mm").format(s.newStart)} – ${DateFormat("HH:mm").format(s.newEnd)}',
            style: const TextStyle(color: _accent, fontSize: 11)),
        Text(s.reason, style: const TextStyle(color: _subtext, fontSize: 11)),
      ])),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: () => onAccept(s),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.18), borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _accent.withOpacity(0.4))),
          child: const Text('Accept',
              style: TextStyle(color: Color(0xFF9B7FFF), fontSize: 11, fontWeight: FontWeight.w600)),
        ),
      ),
    ]),
  );
}


// ═══════════════════════════════════════════════════════════════
// lib/widgets/schedule/briefing_banner.dart
// ═══════════════════════════════════════════════════════════════

class BriefingBanner extends StatelessWidget {
  final DailyBriefing briefing;
  const BriefingBanner({super.key, required this.briefing});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF1E1540), Color(0xFF12122A)],
        begin: Alignment.topLeft, end: Alignment.bottomRight),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _accent.withOpacity(0.22)),
    ),
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_accent, Color(0xFFAA80FF)]),
            borderRadius: BorderRadius.circular(7)),
          alignment: Alignment.center,
          child: const Text('✨', style: TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 10),
        const Text("Samantha's Briefing",
            style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w700)),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: _accent.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
          child: Text('${briefing.events.length} events',
              style: const TextStyle(color: _accent, fontSize: 10, fontWeight: FontWeight.w600)),
        ),
      ]),
      const SizedBox(height: 10),
      Text(briefing.summary, style: const TextStyle(color: _text, fontSize: 13, height: 1.5)),
      if (briefing.insights.isNotEmpty) ...[
        const SizedBox(height: 10),
        Divider(color: const Color(0xFF2A2A4A), height: 1),
        const SizedBox(height: 8),
        ...briefing.insights.map((i) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(i, style: const TextStyle(color: _subtext, fontSize: 12)),
        )),
      ],
      if (briefing.energyAdvice.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: const Color(0xFF0A1628), borderRadius: BorderRadius.circular(9)),
          child: Row(children: [
            const Text('💡', style: TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(child: Text(briefing.energyAdvice,
                style: const TextStyle(color: _subtext, fontSize: 11, height: 1.4))),
          ]),
        ),
      ],
    ]),
  );
}


// ═══════════════════════════════════════════════════════════════
// lib/widgets/schedule/week_strip.dart
// ═══════════════════════════════════════════════════════════════

class WeekStrip extends StatelessWidget {
  final DateTime selected;
  final Function(DateTime) onSelect;
  const WeekStrip({super.key, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dates = List.generate(14, (i) => today.subtract(Duration(days: 3 - i)));
    return SizedBox(
      height: 70,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: dates.length,
        itemBuilder: (_, i) {
          final d = dates[i];
          final isSel = DateFormat('yyyyMMdd').format(d) == DateFormat('yyyyMMdd').format(selected);
          final isToday = DateFormat('yyyyMMdd').format(d) == DateFormat('yyyyMMdd').format(today);
          return GestureDetector(
            onTap: () => onSelect(d),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 46, height: 62,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: isSel ? _accent : const Color(0xFF12122A),
                borderRadius: BorderRadius.circular(13),
                border: isToday && !isSel ? Border.all(color: _accent.withOpacity(0.45)) : null,
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(DateFormat('EEE').format(d).substring(0, 1),
                    style: TextStyle(color: isSel ? Colors.white : _subtext, fontSize: 10)),
                const SizedBox(height: 3),
                Text('${d.day}', style: TextStyle(
                    color: isSel ? Colors.white : _text, fontSize: 16, fontWeight: FontWeight.w700)),
              ]),
            ),
          );
        },
      ),
    );
  }
}


// ═══════════════════════════════════════════════════════════════
// lib/widgets/schedule/add_event_sheet.dart
// ═══════════════════════════════════════════════════════════════

class AddEventSheet extends StatefulWidget {
  final DateTime initialDate;
  final ScheduleEvent? existingEvent;
  final Function(ScheduleEvent) onSave;
  const AddEventSheet({super.key, required this.initialDate,
      this.existingEvent, required this.onSave});
  @override State<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<AddEventSheet> {
  late TextEditingController _title, _desc;
  late DateTime _start, _end;
  EventPriority _priority = EventPriority.medium;
  EventCategory _category = EventCategory.general;

  @override
  void initState() {
    super.initState();
    final e = widget.existingEvent;
    _title = TextEditingController(text: e?.title ?? '');
    _desc  = TextEditingController(text: e?.description ?? '');
    _start = e?.startTime ?? DateTime(widget.initialDate.year,
        widget.initialDate.month, widget.initialDate.day, DateTime.now().hour + 1);
    _end   = e?.endTime ?? _start.add(const Duration(hours: 1));
    _priority = e?.priority ?? EventPriority.medium;
    _category = e?.category ?? EventCategory.general;
  }

  @override
  void dispose() { _title.dispose(); _desc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: Color(0xFF12122A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(children: [
        Center(child: Container(
          margin: const EdgeInsets.only(top: 10),
          width: 38, height: 4,
          decoration: BoxDecoration(color: const Color(0xFF3A3A5C), borderRadius: BorderRadius.circular(2)))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
          child: Row(children: [
            Text(widget.existingEvent != null ? 'Edit Event' : 'New Event',
                style: const TextStyle(color: _text, fontSize: 19, fontWeight: FontWeight.w700)),
            const Spacer(),
            GestureDetector(onTap: () => Navigator.pop(context),
                child: const Icon(Icons.close, color: _subtext)),
          ]),
        ),
        Expanded(child: ListView(padding: const EdgeInsets.all(20), children: [
          _field('Title', _title, hint: 'e.g. Team standup'),
          const SizedBox(height: 12),
          _field('Notes', _desc, hint: 'Optional', maxLines: 2),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _timePicker('Start', _start, (t) => setState(() { _start = t;
                if (_end.isBefore(_start)) _end = _start.add(const Duration(hours: 1)); }))),
            const SizedBox(width: 12),
            Expanded(child: _timePicker('End', _end, (t) => setState(() => _end = t))),
          ]),
          const SizedBox(height: 12),
          _label('Category'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: EventCategory.values.map((c) {
            final sel = _category == c;
            return GestureDetector(
              onTap: () => setState(() => _category = c),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: sel ? _accent.withOpacity(0.2) : const Color(0xFF1A1A35),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? _accent : const Color(0xFF2A2A4A))),
                child: Text('${c.emoji} ${c.label}', style: TextStyle(
                    color: sel ? _accent : _subtext, fontSize: 12)),
              ),
            );
          }).toList()),
          const SizedBox(height: 12),
          _label('Priority'),
          const SizedBox(height: 8),
          Row(children: EventPriority.values.map((p) {
            final sel = _priority == p;
            final pc = _priorityColor(p);
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _priority = p),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: sel ? pc.withOpacity(0.18) : const Color(0xFF1A1A35),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: sel ? pc : const Color(0xFF2A2A4A))),
                alignment: Alignment.center,
                child: Text(p.name[0].toUpperCase() + p.name.substring(1),
                    style: TextStyle(color: sel ? pc : _subtext,
                        fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ));
          }).toList()),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _save,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_accent, Color(0xFFAA80FF)]),
                borderRadius: BorderRadius.circular(14)),
              alignment: Alignment.center,
              child: Text(widget.existingEvent != null ? 'Save Changes' : 'Add Event',
                  style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
            ),
          ),
        ])),
      ]),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {String? hint, int maxLines = 1}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(label), const SizedBox(height: 6),
        TextField(controller: ctrl, maxLines: maxLines,
            style: const TextStyle(color: _text, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint, hintStyle: const TextStyle(color: _subtext),
              filled: true, fillColor: const Color(0xFF1A1A35),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(color: Color(0xFF2A2A4A))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(color: Color(0xFF2A2A4A))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(color: _accent)),
            )),
      ]);

  Widget _timePicker(String label, DateTime val, Function(DateTime) onPick) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _label(label), const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final t = await showTimePicker(
              context: context, initialTime: TimeOfDay.fromDateTime(val),
              builder: (ctx, child) => Theme(
                data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: _accent)),
                child: child!));
            if (t != null) onPick(DateTime(val.year, val.month, val.day, t.hour, t.minute));
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A35), borderRadius: BorderRadius.circular(11),
              border: Border.all(color: const Color(0xFF2A2A4A))),
            child: Row(children: [
              const Icon(Icons.access_time, color: _accent, size: 15),
              const SizedBox(width: 8),
              Text(DateFormat('HH:mm').format(val), style: const TextStyle(color: _text, fontSize: 14)),
            ]),
          ),
        ),
      ]);

  Widget _label(String t) =>
      Text(t, style: const TextStyle(color: _subtext, fontSize: 11, fontWeight: FontWeight.w600));

  Color _priorityColor(EventPriority p) {
    switch (p) {
      case EventPriority.critical: return _danger;
      case EventPriority.high:     return const Color(0xFFFFB74B);
      case EventPriority.medium:   return _accent;
      case EventPriority.low:      return const Color(0xFF4B8BFF);
    }
  }

  void _save() {
    if (_title.text.trim().isEmpty) return;
    widget.onSave(ScheduleEvent(
      id: widget.existingEvent?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: _title.text.trim(),
      description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
      startTime: _start, endTime: _end,
      priority: _priority, category: _category,
    ));
    Navigator.pop(context);
  }
}

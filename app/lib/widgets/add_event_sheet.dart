// lib/widgets/add_event_sheet.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/schedule_models.dart';

class AddEventSheet extends StatefulWidget {
  final DateTime initialDate;
  final SamanthaEvent? existingEvent;
  final Color accentColor;
  final Function(SamanthaEvent) onSave;

  const AddEventSheet({
    super.key,
    required this.initialDate,
    required this.accentColor,
    required this.onSave,
    this.existingEvent,
  });

  @override
  State<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<AddEventSheet> {
  late TextEditingController _titleCtrl;
  late TextEditingController _descCtrl;
  late DateTime _startTime;
  late DateTime _endTime;
  EventPriority _priority = EventPriority.medium;
  EventCategory _category = EventCategory.general;

  static const Color _bg = Color(0xFF12122A);
  static const Color _card = Color(0xFF1A1A35);
  static const Color _textPrimary = Color(0xFFEEEEFF);
  static const Color _textSecondary = Color(0xFF9090B0);

  @override
  void initState() {
    super.initState();
    final e = widget.existingEvent;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _descCtrl = TextEditingController(text: e?.description ?? '');
    _startTime = e?.startTime ?? DateTime(
      widget.initialDate.year,
      widget.initialDate.month,
      widget.initialDate.day,
      DateTime.now().hour + 1,
    );
    _endTime = e?.endTime ?? _startTime.add(const Duration(hours: 1));
    _priority = e?.priority ?? EventPriority.medium;
    _category = e?.category ?? EventCategory.general;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF3A3A5C),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Text(
                  widget.existingEvent != null ? 'Edit Event' : 'New Event',
                  style: const TextStyle(color: _textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: _textSecondary),
                ),
              ],
            ),
          ),
          // Form
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _field('Title', _titleCtrl, hint: 'e.g. Team standup'),
                const SizedBox(height: 14),
                _field('Description', _descCtrl, hint: 'Optional notes', maxLines: 2),
                const SizedBox(height: 14),

                // Time row
                Row(
                  children: [
                    Expanded(child: _timePicker('Start', _startTime, (t) => setState(() {
                      _startTime = t;
                      if (_endTime.isBefore(_startTime)) {
                        _endTime = _startTime.add(const Duration(hours: 1));
                      }
                    }))),
                    const SizedBox(width: 12),
                    Expanded(child: _timePicker('End', _endTime, (t) => setState(() => _endTime = t))),
                  ],
                ),
                const SizedBox(height: 14),

                // Category
                _label('Category'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 8,
                  children: EventCategory.values.map((c) {
                    final selected = _category == c;
                    return GestureDetector(
                      onTap: () => setState(() => _category = c),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: selected ? widget.accentColor.withOpacity(0.2) : _card,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected ? widget.accentColor : const Color(0xFF2A2A4A),
                          ),
                        ),
                        child: Text(
                          '${c.emoji} ${c.label}',
                          style: TextStyle(
                            color: selected ? widget.accentColor : _textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 14),

                // Priority
                _label('Priority'),
                const SizedBox(height: 8),
                Row(
                  children: EventPriority.values.map((p) {
                    final selected = _priority == p;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _priority = p),
                        child: Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: selected ? _priorityColor(p).withOpacity(0.2) : _card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected ? _priorityColor(p) : const Color(0xFF2A2A4A),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            p.name[0].toUpperCase() + p.name.substring(1),
                            style: TextStyle(
                              color: selected ? _priorityColor(p) : _textSecondary,
                              fontSize: 12, fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),

                // Save button
                GestureDetector(
                  onTap: _save,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [widget.accentColor, const Color(0xFFAA80FF)],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      widget.existingEvent != null ? 'Save Changes' : 'Add Event',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {String? hint, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          style: const TextStyle(color: _textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: _textSecondary),
            filled: true,
            fillColor: _card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2A2A4A)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF2A2A4A)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: widget.accentColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _timePicker(String label, DateTime value, Function(DateTime) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(value),
              builder: (ctx, child) => Theme(
                data: ThemeData.dark().copyWith(
                  colorScheme: ColorScheme.dark(primary: widget.accentColor),
                ),
                child: child!,
              ),
            );
            if (picked != null) {
              onChanged(DateTime(value.year, value.month, value.day, picked.hour, picked.minute));
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(12),
              border: const Border.fromBorderSide(BorderSide(color: Color(0xFF2A2A4A))),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, size: 16, color: widget.accentColor),
                const SizedBox(width: 8),
                Text(DateFormat('HH:mm').format(value),
                    style: const TextStyle(color: _textPrimary, fontSize: 15)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: _textSecondary, fontSize: 12, fontWeight: FontWeight.w600));

  void _save() {
    if (_titleCtrl.text.trim().isEmpty) return;
    final event = SamanthaEvent(
      id: widget.existingEvent?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      startTime: _startTime,
      endTime: _endTime,
      priority: _priority,
      category: _category,
    );
    widget.onSave(event);
    Navigator.pop(context);
  }

  Color _priorityColor(EventPriority p) {
    switch (p) {
      case EventPriority.critical: return const Color(0xFFFF4B6E);
      case EventPriority.high: return const Color(0xFFFFB74B);
      case EventPriority.medium: return const Color(0xFF7C5CFC);
      case EventPriority.low: return const Color(0xFF4B8BFF);
    }
  }
}

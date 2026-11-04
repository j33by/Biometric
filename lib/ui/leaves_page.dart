import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/models.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

/// Excused absences. A duty day with no punches inside a leave shows "On leave"
/// and is not counted as absent.
class LeavesPage extends StatefulWidget {
  const LeavesPage({super.key});
  @override
  State<LeavesPage> createState() => _LeavesPageState();
}

class _LeavesPageState extends State<LeavesPage> {
  int _teacher = 0; // 0 = all

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final today = app.today;
    final list = app.leaves.where((l) => _teacher == 0 || l.teacherId == _teacher).toList();
    final active = list.where((l) => l.covers(today)).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        title: 'Leaves',
        subtitle: '${app.leaves.length} recorded · $active on leave today · a leave turns "absent" into "on leave"',
        actions: [
          if (app.canWrite)
            FilledButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => const LeaveDialog()),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add leave'),
            ),
        ],
      ),
      Row(children: [
        SizedBox(
          width: 280,
          child: DropdownButtonFormField<int>(
            initialValue: _teacher,
            isExpanded: true,
            decoration: const InputDecoration(),
            items: [
              const DropdownMenuItem(value: 0, child: Text('All teachers')),
              for (final t in app.teachers) DropdownMenuItem(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _teacher = v ?? 0),
          ),
        ),
        const Spacer(),
        Text('${list.length} shown', style: const TextStyle(color: C.muted)),
      ]),
      const SizedBox(height: 12),
      Expanded(
        child: Container(
          decoration: BoxDecoration(color: C.surface, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(4)),
          child: Column(children: [
            const THead(['Teacher', 'Type', 'From', 'To', 'Days', 'Status', 'Note', ''], [null, 150, 100, 100, 50, 90, 200, 80]),
            Expanded(
              child: list.isEmpty
                  ? const EmptyNote('No leaves recorded.')
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (c, i) {
                        final l = list[i];
                        final name = app.teacherById(l.teacherId)?.name ?? 'ID ${l.teacherId}';
                        final status = l.covers(today) ? const Tag('Now', fg: C.accent, bg: C.accentSoft) : (l.to.isBefore(today) ? const Tag('Past', fg: C.muted, bg: C.surfaceAlt) : const Tag('Upcoming', fg: C.ok, bg: C.okSoft));
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(color: i.isOdd ? C.surfaceAlt : C.surface, border: const Border(bottom: BorderSide(color: C.border, width: 0.5))),
                          child: Row(children: [
                            tcell(Text(name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)), null),
                            tcell(Text(l.type), 150),
                            tcell(Text(fmtDateLong(l.from), style: const TextStyle(fontSize: 12.5)), 100),
                            tcell(Text(fmtDateLong(l.to), style: const TextStyle(fontSize: 12.5)), 100),
                            tcell(Text('${l.days}', style: const TextStyle(color: C.muted)), 50),
                            tcell(Align(alignment: Alignment.centerLeft, child: status), 90),
                            tcell(Text(l.note.isEmpty ? '–' : l.note, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted)), 200),
                            tcell(
                              app.canWrite
                                  ? Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                      IconButton(
                                        tooltip: 'Edit',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.edit_outlined, size: 18),
                                        onPressed: () => showDialog(context: context, builder: (_) => LeaveDialog(existing: l)),
                                      ),
                                      IconButton(
                                        tooltip: 'Delete',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(Icons.delete_outline, size: 18, color: C.bad),
                                        onPressed: () async {
                                          if (await confirm(context, 'Delete this leave?', '$name · ${l.type}. Their days go back to counting as absent if no punch was recorded.')) {
                                            app.deleteLeave(l.id);
                                          }
                                        },
                                      ),
                                    ])
                                  : const SizedBox.shrink(),
                              80,
                            ),
                          ]),
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 20),
    ]);
  }
}

class LeaveDialog extends StatefulWidget {
  final LeaveRecord? existing;
  final int? teacherId; // preselected teacher when opened from a teacher's page
  const LeaveDialog({super.key, this.existing, this.teacherId});
  @override
  State<LeaveDialog> createState() => _LeaveDialogState();
}

class _LeaveDialogState extends State<LeaveDialog> {
  int? _teacher;
  late DateTime _from;
  late DateTime _to;
  String _type = kLeaveTypes.first;
  final _note = TextEditingController();
  String? _error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final e = widget.existing;
    final today = context.app.today;
    _teacher = e?.teacherId ?? widget.teacherId;
    _from = e?.from ?? today;
    _to = e?.to ?? today;
    _type = e?.type ?? kLeaveTypes.first;
    _note.text = e?.note ?? '';
  }

  Future<void> _pick(bool from) async {
    final d = await showDatePicker(context: context, initialDate: from ? _from : _to, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d == null) return;
    setState(() {
      if (from) {
        _from = dateOnly(d);
        if (_to.isBefore(_from)) _to = _from;
      } else {
        _to = dateOnly(d);
        if (_to.isBefore(_from)) _from = _to;
      }
    });
  }

  void _save() {
    if (_teacher == null) {
      setState(() => _error = 'Choose the teacher.');
      return;
    }
    final app = context.app;
    final l = widget.existing?.copy() ?? LeaveRecord(id: app.newLeaveId(), teacherId: _teacher!, from: _from, to: _to);
    l
      ..teacherId = _teacher!
      ..from = _from
      ..to = _to
      ..type = _type
      ..note = _note.text.trim();
    app.saveLeave(l);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final days = _to.difference(_from).inDays + 1;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add leave' : 'Edit leave', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownButtonFormField<int>(
            initialValue: _teacher,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Teacher'),
            items: [for (final t in app.teachers) DropdownMenuItem(value: t.id, child: Text(t.name, overflow: TextOverflow.ellipsis))],
            onChanged: widget.teacherId != null ? null : (v) => setState(() => _teacher = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Type'),
            items: [for (final t in kLeaveTypes) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => _pick(true), icon: const Icon(Icons.calendar_today_outlined, size: 15), label: Text('From ${fmtDateLong(_from)}'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton.icon(onPressed: () => _pick(false), icon: const Icon(Icons.calendar_today_outlined, size: 15), label: Text('To ${fmtDateLong(_to)}'))),
          ]),
          const SizedBox(height: 6),
          Text('$days day${days == 1 ? '' : 's'} (weekends and days without duty are ignored automatically)', style: const TextStyle(fontSize: 12, color: C.muted)),
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: C.bad))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: C.muted))),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/models.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

/// Sections (device "departments"), the 10 shifts and the attendance rules.
class SectionsPage extends StatelessWidget {
  const SectionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      PageHeader(
        title: 'Sections & shifts',
        subtitle: 'Written to the "Attendance Rules Form" sheet of Employee_Form.xls',
        actions: [
          if (app.canWrite) OutlinedButton.icon(onPressed: () => showDialog(context: context, builder: (_) => const RulesDialog()), icon: const Icon(Icons.rule, size: 16), label: const Text('Attendance rules')),
        ],
      ),
      Panel(
        title: 'Sections (device allows 16)',
        padding: EdgeInsets.zero,
        child: Column(children: [
          const THead(['No.', 'Name', 'Weekly shifts (Sun … Sat)', 'Students', ''], [50, null, 330, 80, 60]),
          for (var i = 1; i <= 16; i++) _sectionRow(context, app.sections[i]!, i),
        ]),
      ),
      const SizedBox(height: 16),
      Panel(
        title: 'Shifts (device allows 10)',
        padding: EdgeInsets.zero,
        child: Column(children: [
          const THead(['No.', 'Period 1', 'Period 2', 'Overtime', ''], [50, null, 200, 200, 60]),
          for (var i = 1; i <= 10; i++) _shiftRow(context, app.shifts[i]!),
        ]),
      ),
      const SizedBox(height: 16),
      Panel(
        title: 'Rules in force',
        child: Wrap(spacing: 40, runSpacing: 10, children: [
          _kv('School', app.rules.company.isEmpty ? '–' : app.rules.company),
          _kv('Late allowance', '${app.rules.lateAllow} min'),
          _kv('Early-leave allowance', '${app.rules.earlyAllow} min'),
          _kv('Repeat-scan window', '${app.rules.repeatMin} min'),
          _kv('Schedule from', app.rules.scheduleMode == 0 ? 'Section' : 'Individual'),
        ]),
      ),
    ]);
  }

  Widget _kv(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k.toUpperCase(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: C.muted)),
        const SizedBox(height: 3),
        Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ]);

  Widget _sectionRow(BuildContext context, Section s, int i) {
    final app = context.app;
    final count = app.students.where((x) => x.section == s.no).length;
    final named = s.name.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: i.isEven ? C.surfaceAlt : C.surface, border: const Border(bottom: BorderSide(color: C.border, width: 0.5))),
      child: Row(children: [
        tcell(Text('${s.no}', style: const TextStyle(color: C.muted)), 50),
        tcell(Text(named ? s.name : '(unused)', style: TextStyle(fontWeight: FontWeight.w600, color: named ? C.ink : C.faint)), null),
        tcell(
          Row(children: [
            for (var d = 0; d < 7; d++)
              Container(
                width: 40,
                margin: const EdgeInsets.only(right: 4),
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(color: s.week[d] == 0 ? C.surfaceAlt : C.accentSoft, borderRadius: BorderRadius.circular(2)),
                child: Column(children: [
                  Text(kWeekdayShort[d], style: const TextStyle(fontSize: 9.5, color: C.muted)),
                  Text(s.week[d] == 0 ? '–' : 'S${s.week[d]}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                ]),
              ),
          ]),
          330,
        ),
        tcell(Text('$count', style: const TextStyle(color: C.muted)), 80),
        tcell(app.canWrite ? IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => showDialog(context: context, builder: (_) => SectionDialog(section: s))) : const SizedBox.shrink(), 60),
      ]),
    );
  }

  Widget _shiftRow(BuildContext context, Shift s) {
    final app = context.app;
    String span(String a, String b) => (a.isEmpty || b.isEmpty) ? '–' : '$a – $b';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: s.no.isOdd ? C.surfaceAlt : C.surface, border: const Border(bottom: BorderSide(color: C.border, width: 0.5))),
      child: Row(children: [
        tcell(Text('${s.no}', style: const TextStyle(color: C.muted)), 50),
        tcell(Text(span(s.in1, s.out1), style: TextStyle(fontWeight: FontWeight.w600, color: s.isEmpty ? C.faint : C.ink)), null),
        tcell(Text(span(s.in2, s.out2), style: const TextStyle(color: C.muted)), 200),
        tcell(Text(span(s.otIn, s.otOut), style: const TextStyle(color: C.muted)), 200),
        tcell(app.canWrite ? IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => showDialog(context: context, builder: (_) => ShiftDialog(shift: s))) : const SizedBox.shrink(), 60),
      ]),
    );
  }
}

class SectionDialog extends StatefulWidget {
  final Section section;
  const SectionDialog({super.key, required this.section});
  @override
  State<SectionDialog> createState() => _SectionDialogState();
}

class _SectionDialogState extends State<SectionDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.section.name);
  late final List<int> _week = List<int>.from(widget.section.week);

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return AlertDialog(
      title: Text('Section ${widget.section.no}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Section name (e.g. Grade 10 – Rizal)')),
          const SizedBox(height: 16),
          const Text('Shift for each weekday  (0 = no class)', style: TextStyle(color: C.muted)),
          const SizedBox(height: 8),
          Row(children: [
            for (var d = 0; d < 7; d++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Column(children: [
                    Text(kWeekdayShort[d], style: const TextStyle(fontSize: 12, color: C.muted)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<int>(
                      initialValue: _week[d],
                      isExpanded: true,
                      decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8)),
                      items: [for (var n = 0; n <= 10; n++) DropdownMenuItem(value: n, child: Text('$n'))],
                      onChanged: (v) => setState(() => _week[d] = v ?? 0),
                    ),
                  ]),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() {
                for (var d = 0; d < 7; d++) {
                  _week[d] = (d == 0 || d == 6) ? 0 : 1;
                }
              }),
              child: const Text('Weekdays on shift 1, weekends off'),
            ),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: C.muted))),
        FilledButton(
          onPressed: () {
            final s = widget.section.copy()
              ..name = _name.text.trim()
              ..week = _week;
            app.saveSection(s);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class ShiftDialog extends StatefulWidget {
  final Shift shift;
  const ShiftDialog({super.key, required this.shift});
  @override
  State<ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends State<ShiftDialog> {
  late final Map<String, TextEditingController> _c = {
    'in1': TextEditingController(text: widget.shift.in1),
    'out1': TextEditingController(text: widget.shift.out1),
    'in2': TextEditingController(text: widget.shift.in2),
    'out2': TextEditingController(text: widget.shift.out2),
    'otIn': TextEditingController(text: widget.shift.otIn),
    'otOut': TextEditingController(text: widget.shift.otOut),
  };
  String? _error;

  Widget _f(String key, String label) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(controller: _c[key], decoration: InputDecoration(labelText: label, hintText: 'HH:MM')),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Shift ${widget.shift.no}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Leave a period empty if it is not used. Times are 24-hour, e.g. 08:00 and 17:00.', style: TextStyle(color: C.muted)),
          const SizedBox(height: 14),
          Row(children: [_f('in1', 'Period 1 – in'), _f('out1', 'Period 1 – out')]),
          const SizedBox(height: 12),
          Row(children: [_f('in2', 'Period 2 – in'), _f('out2', 'Period 2 – out')]),
          const SizedBox(height: 12),
          Row(children: [_f('otIn', 'Overtime – in'), _f('otOut', 'Overtime – out')]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: C.bad))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: C.muted))),
        FilledButton(
          onPressed: () {
            String norm(String key) {
              final t = _c[key]!.text.trim();
              if (t.isEmpty) return '';
              final m = parseHm(t);
              return m == null ? 'x' : fmtHm(m);
            }

            final v = {for (final k in _c.keys) k: norm(k)};
            if (v.values.any((e) => e == 'x')) {
              setState(() => _error = 'Use the HH:MM format, for example 07:30.');
              return;
            }
            final s = widget.shift.copy()
              ..in1 = v['in1']!
              ..out1 = v['out1']!
              ..in2 = v['in2']!
              ..out2 = v['out2']!
              ..otIn = v['otIn']!
              ..otOut = v['otOut']!;
            context.app.saveShift(s);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class RulesDialog extends StatefulWidget {
  const RulesDialog({super.key});
  @override
  State<RulesDialog> createState() => _RulesDialogState();
}

class _RulesDialogState extends State<RulesDialog> {
  late final TextEditingController _company, _late, _early, _repeat;
  int _mode = 0;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final r = context.app.rules;
    _company = TextEditingController(text: r.company);
    _late = TextEditingController(text: '${r.lateAllow}');
    _early = TextEditingController(text: '${r.earlyAllow}');
    _repeat = TextEditingController(text: '${r.repeatMin}');
    _mode = r.scheduleMode;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Attendance rules', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 440,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _company, decoration: const InputDecoration(labelText: 'School / company name')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _late, decoration: const InputDecoration(labelText: 'Late allowance (min)'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _early, decoration: const InputDecoration(labelText: 'Early-leave allowance (min)'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _repeat, decoration: const InputDecoration(labelText: 'Ignore repeat scans within (min)'))),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: _mode,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Schedule taken from'),
                items: const [DropdownMenuItem(value: 0, child: Text('Section')), DropdownMenuItem(value: 1, child: Text('Individual'))],
                onChanged: (v) => setState(() => _mode = v ?? 0),
              ),
            ),
          ]),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: C.muted))),
        FilledButton(
          onPressed: () {
            int n(TextEditingController c, int d) => (int.tryParse(c.text.trim()) ?? d).clamp(0, 600);
            final r = context.app.rules.copy()
              ..company = _company.text.trim()
              ..lateAllow = n(_late, 0)
              ..earlyAllow = n(_early, 0)
              ..repeatMin = n(_repeat, 3)
              ..scheduleMode = _mode;
            context.app.saveRules(r);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

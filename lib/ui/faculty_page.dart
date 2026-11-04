import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../core/models.dart';
import '../data/app_state.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

/// Faculty = the device's 16 "Department" slots. Each slot is named after the subject
/// taught and says, for every weekday, which shift (log-in / log-out time) applies.
/// The same slot is called "Department" inside the Excel file because that is what
/// the device reads; the app calls it Faculty / Subject.
class FacultyPage extends StatelessWidget {
  const FacultyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      PageHeader(
        title: 'Faculty & shifts',
        subtitle: 'When each teacher must log in and out · saved to the "Attendance Rules Form" sheet of Employee Form.xls',
        actions: [
          if (app.canWrite) OutlinedButton.icon(onPressed: () => _loadStarter(context), icon: const Icon(Icons.auto_fix_high_outlined, size: 16), label: const Text('Load G12 ABM program')),
          if (app.canWrite) OutlinedButton.icon(onPressed: () => showDialog(context: context, builder: (_) => const RulesDialog()), icon: const Icon(Icons.rule, size: 16), label: const Text('Attendance rules')),
        ],
      ),
      Panel(
        title: 'Faculty schedules · device allows 16',
        padding: EdgeInsets.zero,
        child: Column(children: [
          const THead(['No.', 'Subject', 'Teacher', 'Log-in / log-out by weekday', ''], [44, 150, 170, null, 50]),
          for (var i = 1; i <= 16; i++) _facultyRow(context, app.faculty[i]!, i),
        ]),
      ),
      const SizedBox(height: 16),
      Panel(
        title: 'Shifts · device allows 10 · Philippine time (UTC+8)',
        trailing: const Padding(padding: EdgeInsets.only(right: 4), child: PhClock(showSeconds: false, style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w600))),
        padding: EdgeInsets.zero,
        child: Column(children: [
          const THead(['No.', 'Log-in – log-out', 'Period 2', 'Overtime', 'Used by', ''], [44, null, 190, 190, 200, 50]),
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
          _kv('Schedule from', app.rules.scheduleMode == 0 ? 'Faculty slot' : 'Individual'),
          _kv('Device clock correction', app.rules.clockOffsetMin == 0 ? 'none (device shows PH time)' : '${app.rules.clockOffsetMin > 0 ? '+' : ''}${app.rules.clockOffsetMin} min'),
        ]),
      ),
    ]);
  }

  Future<void> _loadStarter(BuildContext context) async {
    final app = context.app;
    final ok = await confirm(
      context,
      'Load the Grade 12 ABM class program?',
      'This overwrites teachers with device IDs 4-8, all 16 faculty slots and all 10 shifts with the schedule from the class program photo '
      '(Mejorada, Ruloma, Labrador, Sanchez, Pulmano). Other teachers are not touched.',
      action: 'Load',
      danger: false,
    );
    if (ok) {
      app.loadStarterSchedule();
      if (context.mounted) toast(context, 'Class program loaded.');
    }
  }

  Widget _kv(String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k.toUpperCase(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: C.muted)),
        const SizedBox(height: 3),
        Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ]);

  Widget _facultyRow(BuildContext context, Faculty f, int i) {
    final app = context.app;
    final people = app.teachers.where((x) => x.faculty == f.no).map((x) => x.name).toList();
    final named = f.name.trim().isNotEmpty;
    final used = f.week.any((x) => x != 0);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(color: i.isEven ? C.surfaceAlt : C.surface, border: const Border(bottom: BorderSide(color: C.border, width: 0.5))),
      child: Row(children: [
        tcell(Text('${f.no}', style: const TextStyle(color: C.muted)), 44),
        tcell(Text(named ? f.name : '(unused)', style: TextStyle(fontWeight: FontWeight.w600, color: named ? C.ink : C.faint)), 150),
        tcell(Text(people.isEmpty ? '–' : people.join(', '), style: TextStyle(fontSize: 12.5, color: people.isEmpty ? C.faint : C.ink), maxLines: 2, overflow: TextOverflow.ellipsis), 170),
        tcell(named || used ? WeekTimes(faculty: f, shifts: app.shifts, fontSize: 10.5) : const Text('', style: TextStyle(color: C.faint)), null),
        tcell(app.canWrite ? IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => showDialog(context: context, builder: (_) => FacultyDialog(faculty: f))) : const SizedBox.shrink(), 50),
      ]),
    );
  }

  Widget _shiftRow(BuildContext context, Shift s) {
    final app = context.app;
    String span(String a, String b) => (a.isEmpty || b.isEmpty) ? '–' : fmtRange12(a, b);
    final users = app.faculty.values.where((f) => f.name.trim().isNotEmpty && f.week.contains(s.no)).map((f) => f.name).toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: s.no.isOdd ? C.surfaceAlt : C.surface, border: const Border(bottom: BorderSide(color: C.border, width: 0.5))),
      child: Row(children: [
        tcell(Text('${s.no}', style: const TextStyle(color: C.muted)), 44),
        tcell(
          Row(children: [
            Text(span(s.in1, s.out1), style: TextStyle(fontWeight: FontWeight.w600, color: s.isEmpty ? C.faint : C.ink)),
            if (!s.isEmpty) Padding(padding: const EdgeInsets.only(left: 8), child: Text('(${s.in1} – ${s.out1})', style: const TextStyle(fontSize: 11, color: C.faint))),
          ]),
          null,
        ),
        tcell(Text(span(s.in2, s.out2), style: const TextStyle(color: C.muted)), 190),
        tcell(Text(span(s.otIn, s.otOut), style: const TextStyle(color: C.muted)), 190),
        tcell(Text(users.isEmpty ? (s.isEmpty ? '' : 'not used') : users.join(', '), overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: C.muted)), 200),
        tcell(app.canWrite ? IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.edit_outlined, size: 18), onPressed: () => showDialog(context: context, builder: (_) => ShiftDialog(shift: s))) : const SizedBox.shrink(), 50),
      ]),
    );
  }
}

class FacultyDialog extends StatefulWidget {
  final Faculty faculty;
  const FacultyDialog({super.key, required this.faculty});
  @override
  State<FacultyDialog> createState() => _FacultyDialogState();
}

class _FacultyDialogState extends State<FacultyDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.faculty.name);
  late final List<int> _week = List<int>.from(widget.faculty.week);

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final people = app.teachers.where((x) => x.faculty == widget.faculty.no).map((x) => x.name).toList();
    return AlertDialog(
      title: Text('Faculty schedule ${widget.faculty.no}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Subject (e.g. Research 12) - the device prints this next to every punch')),
            const SizedBox(height: 4),
            Text(people.isEmpty ? 'No teacher is assigned to this slot yet (assign it on the Teachers page).' : 'Teacher: ${people.join(', ')}', style: const TextStyle(fontSize: 12, color: C.muted)),
            const SizedBox(height: 16),
            const Text('Which shift applies on each weekday  (0 = no duty)', style: TextStyle(color: C.muted)),
            const SizedBox(height: 8),
            for (var d = 1; d <= 7; d++) _dayRow(d % 7, app),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  for (var d = 0; d < 7; d++) {
                    _week[d] = (d == 0 || d == 6) ? 0 : 1;
                  }
                }),
                child: const Text('Weekdays on shift 1, weekend off'),
              ),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: C.muted))),
        FilledButton(
          onPressed: () {
            final s = widget.faculty.copy()
              ..name = _name.text.trim()
              ..week = _week;
            app.saveFaculty(s);
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _dayRow(int d, AppState app) {
    final shift = _week[d] == 0 ? null : app.shifts[_week[d]];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        SizedBox(width: 92, child: Text(kWeekdayLong[d], style: const TextStyle(fontWeight: FontWeight.w600))),
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<int>(
            initialValue: _week[d],
            isExpanded: true,
            decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
            items: [
              const DropdownMenuItem(value: 0, child: Text('0 · no duty')),
              for (var n = 1; n <= 10; n++) DropdownMenuItem(value: n, child: Text('Shift $n')),
            ],
            onChanged: (v) => setState(() => _week[d] = v ?? 0),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            _week[d] == 0 ? '' : (shift == null || shift.isEmpty ? 'shift ${_week[d]} has no times yet' : 'logs in ${fmtHm12(parseHm(shift.in1)!)} · logs out ${fmtHm12(parseHm(shift.hasSecondPeriod ? shift.out2 : shift.out1)!)}'),
            style: TextStyle(fontSize: 12.5, color: shift == null || shift.isEmpty ? C.warn : C.muted),
          ),
        ),
      ]),
    );
  }
}

/// Shift times are entered in Philippine time (12-hour "7:50 AM" or 24-hour "13:00")
/// and stored as 24-hour "HH:mm" - exactly what the device's own Employee Form holds.
/// Nothing here ever depends on the computer's time zone.
class ShiftDialog extends StatefulWidget {
  final Shift shift;
  const ShiftDialog({super.key, required this.shift});
  @override
  State<ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends State<ShiftDialog> {
  static const _keys = ['in1', 'out1', 'in2', 'out2', 'otIn', 'otOut'];
  late final Map<String, TextEditingController> _c = {
    for (final k in _keys) k: TextEditingController(text: _initial(k)),
  };
  String? _error;
  List<String> _warnings = const [];
  bool _acknowledged = false;

  String _initial(String k) {
    final v = {
      'in1': widget.shift.in1,
      'out1': widget.shift.out1,
      'in2': widget.shift.in2,
      'out2': widget.shift.out2,
      'otIn': widget.shift.otIn,
      'otOut': widget.shift.otOut,
    }[k]!;
    final m = parseHm(v);
    return m == null ? '' : fmtHm12(m);
  }

  Future<void> _pickTime(String key) async {
    final cur = normalizeTimeInput(_c[key]!.text);
    final m = cur == null ? 8 * 60 : parseHm(cur)!;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
      helpText: 'Philippine time',
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false), child: child!),
    );
    if (t == null) return;
    setState(() {
      _c[key]!.text = fmtHm12(t.hour * 60 + t.minute);
      _acknowledged = false;
      _warnings = const [];
    });
  }

  Widget _f(String key, String label) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: TextField(
            controller: _c[key],
            onChanged: (_) => setState(() {
              _acknowledged = false;
              _warnings = const [];
            }),
            decoration: InputDecoration(
              labelText: label,
              hintText: '7:50 AM',
              helperText: _helper(key),
              suffixIcon: IconButton(tooltip: 'Pick a time', icon: const Icon(Icons.access_time, size: 17), onPressed: () => _pickTime(key)),
            ),
          ),
        ),
      );

  String _helper(String key) {
    final t = _c[key]!.text.trim();
    if (t.isEmpty) return ' ';
    final n = normalizeTimeInput(t);
    return n == null ? 'not a time' : 'saved as $n (${fmtHm12(parseHm(n)!)})';
  }

  void _save() {
    final v = <String, String>{};
    for (final k in _keys) {
      final t = _c[k]!.text.trim();
      if (t.isEmpty) {
        v[k] = '';
        continue;
      }
      final n = normalizeTimeInput(t);
      if (n == null) {
        setState(() => _error = 'Could not read "$t". Use 7:50 AM, 1:00 PM or 13:00.');
        return;
      }
      v[k] = n;
    }

    // each period needs both ends, and the end must come after the start
    final pairs = [('in1', 'out1', 'Period 1'), ('in2', 'out2', 'Period 2'), ('otIn', 'otOut', 'Overtime')];
    for (final p in pairs) {
      final a = v[p.$1]!, b = v[p.$2]!;
      if (a.isEmpty != b.isEmpty) {
        setState(() => _error = '${p.$3}: fill in both the log-in and the log-out time, or leave both empty.');
        return;
      }
      if (a.isNotEmpty && parseHm(b)! <= parseHm(a)!) {
        setState(() => _error = '${p.$3}: the log-out time must be later than the log-in time (${fmtHm12(parseHm(a)!)} → ${fmtHm12(parseHm(b)!)}).');
        return;
      }
    }
    if (v['in2']!.isNotEmpty && v['in1']!.isEmpty) {
      setState(() => _error = 'Fill in Period 1 before Period 2.');
      return;
    }
    if (v['in2']!.isNotEmpty && parseHm(v['in2']!)! < parseHm(v['out1']!)!) {
      setState(() => _error = 'Period 2 must start after Period 1 ends.');
      return;
    }

    // Not an error, but the classic mistake: "1:00" typed for 1 PM is saved as 1 AM.
    final warn = <String>[];
    for (final k in ['in1', 'out1', 'in2', 'out2']) {
      final m = v[k]!.isEmpty ? null : parseHm(v[k]!);
      if (m != null && (m < 5 * 60 || m > 21 * 60)) warn.add('${fmtHm12(m)} is outside normal school hours.');
    }
    if (warn.isNotEmpty && !_acknowledged) {
      setState(() {
        _error = null;
        _warnings = warn;
        _acknowledged = true;
      });
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
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Shift ${widget.shift.no}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 560,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: C.accentSoft, borderRadius: BorderRadius.circular(3)),
            child: Row(children: [
              const Icon(Icons.public, size: 16, color: C.accent),
              const SizedBox(width: 8),
              const Expanded(child: Text('Times are Philippine time (UTC+8). Type 7:50 AM, 1:00 PM or 13:00: the Employee Form always gets 24-hour times, so the device and this app read the same clock.', style: TextStyle(fontSize: 12, height: 1.35))),
              const SizedBox(width: 10),
              const PhClock(showSeconds: false, style: TextStyle(fontWeight: FontWeight.w700, color: C.accent, fontSize: 12.5)),
            ]),
          ),
          const SizedBox(height: 14),
          const Text('Leave a period empty if it is not used. One continuous class block is just Period 1.', style: TextStyle(color: C.muted, fontSize: 12.5)),
          const SizedBox(height: 10),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [_f('in1', 'Period 1 – log in'), _f('out1', 'Period 1 – log out')]),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [_f('in2', 'Period 2 – log in'), _f('out2', 'Period 2 – log out')]),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [_f('otIn', 'Overtime – in'), _f('otOut', 'Overtime – out')]),
          if (_warnings.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: C.warnSoft, borderRadius: BorderRadius.circular(3)),
              child: Text('${_warnings.join('\n')}\nIf you meant PM, type it as 1:00 PM. Press Save again to keep it as it is.', style: const TextStyle(color: C.warn, fontSize: 12.5, height: 1.4)),
            ),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: C.bad))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: C.muted))),
        FilledButton(onPressed: _save, child: Text(_acknowledged ? 'Save anyway' : 'Save')),
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
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: _company, decoration: const InputDecoration(labelText: 'School name')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: TextField(controller: _late, decoration: const InputDecoration(labelText: 'Late allowance (min)', helperText: 'grace after the log-in time'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _early, decoration: const InputDecoration(labelText: 'Early-leave allowance (min)', helperText: 'grace before the log-out time'))),
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
                items: const [DropdownMenuItem(value: 0, child: Text('Faculty slot')), DropdownMenuItem(value: 1, child: Text('Individual'))],
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

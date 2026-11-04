import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/attendance.dart';
import '../core/dates.dart';
import '../core/models.dart';
import '../data/app_state.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});
  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  DateTime? _day;
  DayStatus? _filter;
  int _faculty = 0;
  bool _raw = false;
  final _search = TextEditingController();

  DateTime _effectiveDay(BuildContext context) {
    if (_day != null) return _day!;
    final app = context.app;
    final today = app.today; // Philippine date
    if (app.book.hasData(today) || app.logsByDate.isEmpty) return today;
    String best = '';
    for (final k in app.logsByDate.keys) {
      if (k.compareTo(best) > 0) best = k;
    }
    return parseDate(best) ?? today;
  }

  Future<void> _pick(DateTime current) async {
    final d = await showDatePicker(context: context, initialDate: current, firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d != null) setState(() => _day = dateOnly(d));
  }

  Future<void> _export(DateTime day) async {
    final app = context.app;
    final path = await FilePicker.platform.saveFile(dialogTitle: 'Save attendance CSV', fileName: 'attendance_${fmtDate(day)}.csv', type: FileType.custom, allowedExtensions: ['csv']);
    if (path == null) return;
    try {
      await app.writeText(path, app.dayCsv(day));
      if (mounted) toast(context, 'Saved $path');
    } catch (e) {
      if (mounted) toast(context, 'Could not save: $e', error: true);
    }
  }

  Future<void> _exportMonth(DateTime day) async {
    final app = context.app;
    final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save monthly summary CSV',
        fileName: 'attendance_${day.year}-${two(day.month)}_summary.csv',
        type: FileType.custom,
        allowedExtensions: ['csv']);
    if (path == null) return;
    try {
      await app.writeText(path, app.monthCsv(day));
      if (mounted) toast(context, 'Saved $path');
    } catch (e) {
      if (mounted) toast(context, 'Could not save: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final day = _effectiveDay(context);
    final book = app.book;
    final sum = book.summary(day);
    final q = _search.text.trim().toLowerCase();
    final recs = book.day(day).where((r) {
      if (_filter != null && r.status != _filter) return false;
      if (_faculty != 0 && r.teacher.faculty != _faculty) return false;
      if (q.isNotEmpty && !r.teacher.name.toLowerCase().contains(q) && '${r.teacher.id}' != q) return false;
      return true;
    }).toList();
    final raw = [...(app.logsByDate[fmtDate(day)] ?? <PunchLog>[])]..sort((a, b) => a.time.compareTo(b.time));

    Widget chip(String label, DayStatus? s, int n) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text('$label  $n'),
            selected: _filter == s,
            showCheckmark: false,
            onSelected: (_) => setState(() => _filter = s),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3), side: const BorderSide(color: C.border)),
            selectedColor: C.accentSoft,
            backgroundColor: Colors.white,
            labelStyle: const TextStyle(fontSize: 12.5),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        title: 'Attendance',
        subtitle: book.hasData(day) ? '${sum.punches} punches on ${fmtDateLong(day)}' : 'No punches imported for ${fmtDateLong(day)}',
        actions: [
          OutlinedButton.icon(onPressed: () => _exportMonth(day), icon: const Icon(Icons.calendar_month_outlined, size: 16), label: const Text('Export month')),
          OutlinedButton.icon(onPressed: () => _export(day), icon: const Icon(Icons.download_outlined, size: 16), label: const Text('Export day')),
        ],
      ),
      Row(children: [
        IconButton.outlined(onPressed: () => setState(() => _day = day.subtract(const Duration(days: 1))), icon: const Icon(Icons.chevron_left, size: 18), visualDensity: VisualDensity.compact),
        const SizedBox(width: 6),
        OutlinedButton.icon(onPressed: () => _pick(day), icon: const Icon(Icons.calendar_today_outlined, size: 15), label: Text(fmtDateLong(day))),
        const SizedBox(width: 6),
        IconButton.outlined(onPressed: () => setState(() => _day = day.add(const Duration(days: 1))), icon: const Icon(Icons.chevron_right, size: 18), visualDensity: VisualDensity.compact),
        const SizedBox(width: 6),
        TextButton(onPressed: () => setState(() => _day = context.app.today), child: const Text('Today')),
        const Spacer(),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: ButtonStyle(visualDensity: VisualDensity.compact, shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)))),
          segments: const [ButtonSegment(value: false, label: Text('Per teacher')), ButtonSegment(value: true, label: Text('Raw punches'))],
          selected: {_raw},
          onSelectionChanged: (s) => setState(() => _raw = s.first),
        ),
      ]),
      const SizedBox(height: 12),
      if (!_raw)
        Row(children: [
          chip('All', null, sum.expected),
          chip('Present', DayStatus.present, sum.present - sum.late),
          chip('Late', DayStatus.late, sum.late),
          chip('Absent', DayStatus.absent, sum.absent),
          chip('On leave', DayStatus.leave, sum.onLeave),
          const SizedBox(width: 8),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<int>(
              initialValue: _faculty,
              isExpanded: true,
              decoration: const InputDecoration(),
              items: [const DropdownMenuItem(value: 0, child: Text('All subjects')), for (var i = 1; i <= 16; i++) DropdownMenuItem(value: i, child: Text(app.facultyName(i), overflow: TextOverflow.ellipsis))],
              onChanged: (v) => setState(() => _faculty = v ?? 0),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(width: 200, child: TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: 'Search'))),
        ]),
      const SizedBox(height: 12),
      Expanded(
        child: Container(
          decoration: BoxDecoration(color: C.surface, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(4)),
          child: _raw ? _rawTable(app, raw) : _table(app, recs),
        ),
      ),
      const SizedBox(height: 20),
    ]);
  }

  Widget _table(AppState app, List<DayRecord> recs) {
    return Column(children: [
      const THead(['ID', 'Teacher', 'Subject', 'Scheduled', 'Status', 'In', 'Out', 'Late', 'Early out'], [44, null, 140, 140, 84, 76, 76, 70, 76]),
      Expanded(
        child: recs.isEmpty
            ? const EmptyNote('Nothing to show for these filters.')
            : ListView.builder(
                itemCount: recs.length,
                itemBuilder: (c, i) {
                  final r = recs[i];
                  final out = r.out2 ?? r.out1;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: i.isOdd ? C.surfaceAlt : C.surface, border: const Border(bottom: BorderSide(color: C.border, width: 0.5))),
                    child: Row(children: [
                      tcell(Text('${r.teacher.id}', style: const TextStyle(color: C.muted)), 44),
                      tcell(Text(r.teacher.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)), null),
                      tcell(Text(app.facultyName(r.teacher.faculty), overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted)), 140),
                      tcell(Text(r.schedule.isEmpty ? '–' : r.schedule, style: TextStyle(fontSize: 12, color: r.schedule.isEmpty ? C.faint : C.muted)), 140),
                      tcell(Align(alignment: Alignment.centerLeft, child: Tag.status(r.status)), 84),
                      tcell(Text(r.in1 == null ? '–' : fmtTime12(r.in1!), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])), 76),
                      tcell(Text(out == null ? (r.attended ? 'missed' : '–') : fmtTime12(out), style: TextStyle(color: out == null && r.attended ? C.warn : C.ink, fontFeatures: const [FontFeature.tabularFigures()])), 76),
                      tcell(Text(r.lateMin > 0 ? '${r.lateMin} min' : '–', style: TextStyle(color: r.lateMin > 0 ? C.warn : C.faint)), 70),
                      tcell(Text(r.earlyMin > 0 ? '${r.earlyMin} min' : '–', style: TextStyle(color: r.earlyMin > 0 ? C.muted : C.faint)), 76),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _rawTable(AppState app, List<PunchLog> raw) {
    return Column(children: [
      const THead(['Time', 'ID', 'Teacher', 'Subject', 'Device'], [90, 60, null, 180, 70]),
      Expanded(
        child: raw.isEmpty
            ? const EmptyNote('No raw punches for this day.')
            : ListView.builder(
                itemCount: raw.length,
                itemBuilder: (c, i) {
                  final l = raw[i];
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: i.isOdd ? C.surfaceAlt : C.surface, border: const Border(bottom: BorderSide(color: C.border, width: 0.5))),
                    child: Row(children: [
                      tcell(Text(fmtTimeSec(l.time), style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])), 90),
                      tcell(Text('${l.teacherId}', style: const TextStyle(color: C.muted)), 60),
                      tcell(Text(l.name), null),
                      tcell(Text(l.dept, style: const TextStyle(color: C.muted)), 180),
                      tcell(Text('${l.deviceId}', style: const TextStyle(color: C.muted)), 70),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}

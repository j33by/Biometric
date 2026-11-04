import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/attendance.dart';
import '../core/dates.dart';
import '../core/models.dart';
import '../main.dart';
import 'leaves_page.dart';
import 'theme.dart';
import 'widgets.dart';

class TeachersPage extends StatefulWidget {
  const TeachersPage({super.key});
  @override
  State<TeachersPage> createState() => _TeachersPageState();
}

class _TeachersPageState extends State<TeachersPage> {
  final _search = TextEditingController();
  int _faculty = 0; // 0 = all
  int _sort = 0; // 0 id, 1 name

  Future<void> _importForm() async {
    final app = context.app;
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xls'], dialogTitle: 'Choose Employee Form.xls');
    final path = res?.files.single.path;
    if (path == null) return;
    try {
      final n = await app.importFormFile(path);
      if (mounted) toast(context, n == 0 ? 'Nothing new in that file.' : 'Merged $n change${n == 1 ? '' : 's'} from the file.');
    } catch (e) {
      if (mounted) toast(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final q = _search.text.trim().toLowerCase();
    var list = app.teachers.where((s) {
      if (_faculty != 0 && s.faculty != _faculty) return false;
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q) || '${s.id}' == q || s.teacherNo.toLowerCase().contains(q);
    }).toList();
    if (_sort == 1) list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final today = app.today;
    final day = app.book.hasData(today) ? today : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        title: 'Teachers',
        subtitle: '${app.teachers.length} enrolled · changes are written to Employee Form.xls automatically',
        actions: [
          if (app.canWrite) OutlinedButton.icon(onPressed: _importForm, icon: const Icon(Icons.file_open_outlined, size: 16), label: const Text('Import .xls')),
          if (app.canWrite)
            FilledButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => const TeacherDialog()),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add teacher'),
            ),
        ],
      ),
      Row(children: [
        SizedBox(
          width: 300,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: 'Search name, device ID or Teacher ID'),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<int>(
            initialValue: _faculty,
            isExpanded: true,
            decoration: const InputDecoration(),
            items: [
              const DropdownMenuItem(value: 0, child: Text('All subjects')),
              for (var i = 1; i <= 16; i++) DropdownMenuItem(value: i, child: Text(app.facultyName(i), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _faculty = v ?? 0),
          ),
        ),
        const SizedBox(width: 10),
        SegmentedButton<int>(
          showSelectedIcon: false,
          style: ButtonStyle(visualDensity: VisualDensity.compact, shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)))),
          segments: const [ButtonSegment(value: 0, label: Text('By ID')), ButtonSegment(value: 1, label: Text('By name'))],
          selected: {_sort},
          onSelectionChanged: (s) => setState(() => _sort = s.first),
        ),
        const Spacer(),
        Text('${list.length} shown', style: const TextStyle(color: C.muted)),
      ]),
      const SizedBox(height: 12),
      Expanded(
        child: Container(
          decoration: BoxDecoration(color: C.surface, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(4)),
          child: Column(children: [
            const THead(['ID', 'Teacher', 'Subject', 'Teacher ID', 'Duty today', 'Today', ''], [48, null, 160, 110, 150, 84, 96]),
            Expanded(
              child: list.isEmpty
                  ? const EmptyNote('No teachers match.')
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final s = list[i];
                        final rec = day == null ? null : app.book.recordFor(s, day);
                        final sched = app.book.shiftFor(s, today);
                        return InkWell(
                          onTap: () => showDialog(context: context, builder: (_) => TeacherDetail(teacher: s)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(color: i.isOdd ? C.surfaceAlt : C.surface, border: const Border(bottom: BorderSide(color: C.border, width: 0.5))),
                            child: Row(children: [
                              tcell(Text('${s.id}', style: const TextStyle(color: C.muted, fontFeatures: [FontFeature.tabularFigures()])), 48),
                              tcell(
                                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Flexible(child: Text(s.name.isEmpty ? '(no name)' : s.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
                                    if (s.authority == 1) const Padding(padding: EdgeInsets.only(left: 6), child: Tag('Device admin', fg: C.accent, bg: C.accentSoft)),
                                  ]),
                                  if (s.position.isNotEmpty) Text(s.position, style: const TextStyle(fontSize: 11.5, color: C.muted)),
                                ]),
                                null,
                              ),
                              tcell(Text(app.facultyName(s.faculty), overflow: TextOverflow.ellipsis), 160),
                              tcell(Text(s.teacherNo.isEmpty ? '–' : s.teacherNo, style: const TextStyle(color: C.muted)), 110),
                              tcell(Text(sched == null || sched.isEmpty ? 'No duty' : sched.label, style: TextStyle(fontSize: 12.5, color: sched == null ? C.faint : C.ink)), 150),
                              tcell(rec == null ? const Text('–', style: TextStyle(color: C.faint)) : Align(alignment: Alignment.centerLeft, child: Tag.status(rec.status)), 84),
                              tcell(
                                app.canWrite
                                    ? Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                        IconButton(
                                          tooltip: 'Edit',
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.edit_outlined, size: 18),
                                          onPressed: () => showDialog(context: context, builder: (_) => TeacherDialog(existing: s)),
                                        ),
                                        IconButton(
                                          tooltip: 'Remove',
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.delete_outline, size: 18, color: C.bad),
                                          onPressed: () async {
                                            final ok = await confirm(context, 'Remove ${s.name}?', 'They will be removed from the device upload file. Their past attendance records are kept.');
                                            if (ok) app.deleteTeacher(s.id);
                                          },
                                        ),
                                      ])
                                    : const SizedBox.shrink(),
                                96,
                              ),
                            ]),
                          ),
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

class TeacherDialog extends StatefulWidget {
  final Teacher? existing;
  const TeacherDialog({super.key, this.existing});
  @override
  State<TeacherDialog> createState() => _TeacherDialogState();
}

class _TeacherDialogState extends State<TeacherDialog> {
  late final TextEditingController _id, _name, _teacherNo, _position, _contact, _notes;
  int _faculty = 1;
  int _authority = 0;
  String? _error;
  bool _init = false;

  bool get isNew => widget.existing == null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_init) return;
    _init = true;
    final e = widget.existing;
    _id = TextEditingController(text: '${e?.id ?? context.app.nextTeacherId}');
    _name = TextEditingController(text: e?.name ?? '');
    _teacherNo = TextEditingController(text: e?.teacherNo ?? '');
    _position = TextEditingController(text: e?.position ?? '');
    _contact = TextEditingController(text: e?.contact ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _faculty = e?.faculty ?? 1;
    _authority = e?.authority ?? 0;
  }

  void _save() {
    final app = context.app;
    final id = int.tryParse(_id.text.trim());
    if (id == null || id < 1 || id > 99999999) {
      setState(() => _error = 'Device ID must be a positive number.');
      return;
    }
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the teacher\'s name.');
      return;
    }
    final other = app.teacherWithNo(_teacherNo.text, exceptId: widget.existing?.id ?? id);
    if (other != null && other.id != id) {
      setState(() => _error = 'Teacher ID ${_teacherNo.text.trim()} already belongs to ${other.name}.');
      return;
    }
    final s = (widget.existing?.copy() ?? Teacher(id: id, name: ''))
      ..name = _name.text.trim()
      ..faculty = _faculty
      ..authority = _authority
      ..teacherNo = _teacherNo.text.trim()
      ..position = _position.text.trim()
      ..contact = _contact.text.trim()
      ..notes = _notes.text.trim();
    final err = app.saveTeacher(s, isNew: isNew);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    Navigator.pop(context);
    if (isNew) toast(context, 'Added. Enrol their fingerprint on the device under ID $id.');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final fac = app.faculty[_faculty];
    return AlertDialog(
      title: Text(isNew ? 'Add teacher' : 'Edit teacher', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              SizedBox(width: 110, child: TextField(controller: _id, enabled: isNew, decoration: const InputDecoration(labelText: 'Device ID'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Full name (Last, First M.)'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _teacherNo, decoration: const InputDecoration(labelText: 'Teacher ID (employee no.)'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _position, decoration: const InputDecoration(labelText: 'Position (e.g. Teacher I, Adviser)'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _faculty,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Subject (faculty schedule)'),
                  items: [for (var i = 1; i <= 16; i++) DropdownMenuItem(value: i, child: Text(app.facultyName(i), overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => _faculty = v ?? 1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _authority,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Role on the device'),
                  items: const [DropdownMenuItem(value: 0, child: Text('Teacher')), DropdownMenuItem(value: 1, child: Text('Device administrator'))],
                  onChanged: (v) => setState(() => _authority = v ?? 0),
                ),
              ),
            ]),
            if (fac != null) ...[
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: Text('Must log in / out on:', style: const TextStyle(fontSize: 11.5, color: C.muted))),
              const SizedBox(height: 4),
              WeekTimes(faculty: fac, shifts: app.shifts, fontSize: 10.5),
            ],
            const SizedBox(height: 12),
            TextField(controller: _contact, decoration: const InputDecoration(labelText: 'Contact number (optional)')),
            const SizedBox(height: 12),
            TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (stays in this app, not sent to the device)')),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Align(alignment: Alignment.centerLeft, child: Text(_error!, style: const TextStyle(color: C.bad)))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: C.muted))),
        FilledButton(onPressed: _save, child: Text(isNew ? 'Add teacher' : 'Save')),
      ],
    );
  }
}

class TeacherDetail extends StatefulWidget {
  final Teacher teacher;
  const TeacherDetail({super.key, required this.teacher});
  @override
  State<TeacherDetail> createState() => _TeacherDetailState();
}

class _TeacherDetailState extends State<TeacherDetail> {
  late DateTime _month = DateTime(context.app.today.year, context.app.today.month);

  Future<void> _dtr() async {
    final app = context.app;
    final t = widget.teacher;
    final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Daily Time Record',
        fileName: 'DTR_${t.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}_${_month.year}-${two(_month.month)}.csv',
        type: FileType.custom,
        allowedExtensions: ['csv']);
    if (path == null) return;
    try {
      await app.writeText(path, app.dtrCsv(t, _month));
      if (mounted) toast(context, 'Saved $path');
    } catch (e) {
      if (mounted) toast(context, 'Could not save: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final book = app.book;
    final t = widget.teacher;
    final fac = app.faculty[t.faculty];
    final stats = book.month(t, _month);
    final last = DateTime(_month.year, _month.month + 1, 0).day;
    final rows = <DayRecord>[];
    for (var d = last; d >= 1; d--) {
      final r = book.recordFor(t, DateTime(_month.year, _month.month, d));
      if (r == null || r.status == DayStatus.noData || r.status == DayStatus.dayOff) continue;
      rows.add(r);
    }
    final isCurrent = _month.year == app.today.year && _month.month == app.today.month;
    final leaves = app.leavesFor(t.id);
    return AlertDialog(
      title: Row(children: [
        Expanded(child: Text(t.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 18)),
      ]),
      content: SizedBox(
        width: 660,
        height: 560,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              'Device ID ${t.id} · ${app.facultyName(t.faculty)}'
              '${t.teacherNo.isEmpty ? '' : ' · Teacher ID ${t.teacherNo}'}'
              '${t.position.isEmpty ? '' : ' · ${t.position}'}'
              '${t.contact.isEmpty ? '' : ' · ${t.contact}'}',
              style: const TextStyle(color: C.muted)),
          const SizedBox(height: 10),
          if (fac != null) ...[
            const Text('LOG-IN / LOG-OUT SCHEDULE (PHILIPPINE TIME)', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: C.muted)),
            const SizedBox(height: 5),
            WeekTimes(faculty: fac, shifts: app.shifts),
            const SizedBox(height: 12),
          ],
          Row(children: [
            IconButton.outlined(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)), icon: const Icon(Icons.chevron_left, size: 18), visualDensity: VisualDensity.compact),
            const SizedBox(width: 8),
            Text('${kMonthShort[_month.month - 1]} ${_month.year}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(width: 8),
            IconButton.outlined(onPressed: isCurrent ? null : () => setState(() => _month = DateTime(_month.year, _month.month + 1)), icon: const Icon(Icons.chevron_right, size: 18), visualDensity: VisualDensity.compact),
            const Spacer(),
            if (app.canWrite) TextButton.icon(onPressed: () => showDialog(context: context, builder: (_) => LeaveDialog(teacherId: t.id)), icon: const Icon(Icons.event_busy_outlined, size: 16), label: const Text('Add leave')),
            OutlinedButton.icon(onPressed: _dtr, icon: const Icon(Icons.download_outlined, size: 16), label: const Text('Export DTR')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Kpi(label: 'Attendance', value: stats.rate == null ? '–' : '${(stats.rate! * 100).round()}%', note: '${stats.present} of ${stats.scheduledDays} duty days')),
            const SizedBox(width: 10),
            Expanded(child: Kpi(label: 'Late', value: '${stats.late}', color: C.warn, note: fmtDuration(stats.lateMin))),
            const SizedBox(width: 10),
            Expanded(child: Kpi(label: 'Absent', value: '${stats.absent}', color: C.bad, note: stats.leave > 0 ? '${stats.leave} on leave' : null)),
            const SizedBox(width: 10),
            Expanded(child: Kpi(label: 'Hours', value: (stats.workedMin / 60).toStringAsFixed(1), note: 'of ${(stats.scheduledMin / 60).toStringAsFixed(0)} scheduled')),
          ]),
          const SizedBox(height: 10),
          Expanded(
            child: rows.isEmpty
                ? const EmptyNote('No duty days with data this month.')
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (c, i) {
                      final r = rows[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          SizedBox(width: 108, child: Text(fmtDateLong(r.date), style: const TextStyle(fontSize: 12.5))),
                          SizedBox(width: 132, child: Text(r.schedule, style: const TextStyle(fontSize: 12, color: C.muted))),
                          SizedBox(width: 74, child: Align(alignment: Alignment.centerLeft, child: Tag.status(r.status))),
                          const SizedBox(width: 10),
                          SizedBox(width: 74, child: Text(r.in1 == null ? '' : 'in ${fmtTime12(r.in1!)}', style: const TextStyle(color: C.muted, fontSize: 12.5))),
                          Expanded(child: Text(r.lastOut == null ? (r.attended ? 'no log-out' : (r.leaveType ?? '')) : 'out ${fmtTime12(r.lastOut!)}', style: TextStyle(color: r.attended && r.lastOut == null ? C.warn : C.muted, fontSize: 12.5))),
                          if (r.lateMin > 0) Text('${r.lateMin} min late', style: const TextStyle(color: C.warn, fontSize: 12)),
                          if (r.earlyMin > 0) Padding(padding: const EdgeInsets.only(left: 8), child: Text('${r.earlyMin} min early out', style: const TextStyle(color: C.muted, fontSize: 12))),
                        ]),
                      );
                    },
                  ),
          ),
          if (leaves.isNotEmpty) ...[
            const Divider(height: 14),
            Text('Leaves: ${leaves.take(3).map((l) => '${l.type} ${fmtDayMonth(l.from)}${l.days > 1 ? '–${fmtDayMonth(l.to)}' : ''}').join(' · ')}${leaves.length > 3 ? ' …' : ''}', style: const TextStyle(fontSize: 12, color: C.muted)),
          ],
        ]),
      ),
    );
  }
}

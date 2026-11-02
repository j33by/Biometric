import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/attendance.dart';
import '../core/dates.dart';
import '../core/models.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

class StudentsPage extends StatefulWidget {
  const StudentsPage({super.key});
  @override
  State<StudentsPage> createState() => _StudentsPageState();
}

class _StudentsPageState extends State<StudentsPage> {
  final _search = TextEditingController();
  int _section = 0; // 0 = all
  int _sort = 0; // 0 id, 1 name

  Future<void> _importForm() async {
    final app = context.app;
    final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xls'], dialogTitle: 'Choose Employee_Form.xls');
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
    var list = app.students.where((s) {
      if (_section != 0 && s.section != _section) return false;
      if (q.isEmpty) return true;
      return s.name.toLowerCase().contains(q) || '${s.id}' == q || s.lrn.toLowerCase().contains(q);
    }).toList();
    if (_sort == 1) list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final today = dateOnly(DateTime.now());
    final day = app.book.hasData(today) ? today : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        title: 'Students',
        subtitle: '${app.students.length} enrolled · changes are written to Employee_Form.xls automatically',
        actions: [
          if (app.canWrite) OutlinedButton.icon(onPressed: _importForm, icon: const Icon(Icons.file_open_outlined, size: 16), label: const Text('Import .xls')),
          if (app.canWrite)
            FilledButton.icon(
              onPressed: () => showDialog(context: context, builder: (_) => const StudentDialog()),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add student'),
            ),
        ],
      ),
      Row(children: [
        SizedBox(
          width: 300,
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: 'Search name, ID or LRN'),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<int>(
            initialValue: _section,
            isExpanded: true,
            decoration: const InputDecoration(),
            items: [
              const DropdownMenuItem(value: 0, child: Text('All sections')),
              for (var i = 1; i <= 16; i++) DropdownMenuItem(value: i, child: Text(app.sectionName(i), overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _section = v ?? 0),
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
            const THead(['ID', 'Name', 'Section', 'Device role', 'LRN', 'Today', ''], [60, null, 190, 110, 130, 90, 96]),
            Expanded(
              child: list.isEmpty
                  ? const EmptyNote('No students match.')
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (context, i) {
                        final s = list[i];
                        final rec = day == null ? null : app.book.recordFor(s, day);
                        return InkWell(
                          onTap: () => showDialog(context: context, builder: (_) => StudentDetail(student: s)),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                            decoration: BoxDecoration(color: i.isOdd ? C.surfaceAlt : C.surface, border: const Border(bottom: BorderSide(color: C.border, width: 0.5))),
                            child: Row(children: [
                              tcell(Text('${s.id}', style: const TextStyle(color: C.muted, fontFeatures: [FontFeature.tabularFigures()])), 60),
                              tcell(Text(s.name.isEmpty ? '(no name)' : s.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)), null),
                              tcell(Text(app.sectionName(s.section), overflow: TextOverflow.ellipsis), 190),
                              tcell(s.authority == 1 ? const Align(alignment: Alignment.centerLeft, child: Tag('Admin', fg: C.accent, bg: C.accentSoft)) : const Text('Student', style: TextStyle(color: C.muted)), 110),
                              tcell(Text(s.lrn.isEmpty ? '–' : s.lrn, style: const TextStyle(color: C.muted)), 130),
                              tcell(rec == null ? const Text('–', style: TextStyle(color: C.faint)) : Align(alignment: Alignment.centerLeft, child: Tag.status(rec.status)), 90),
                              tcell(
                                app.canWrite
                                    ? Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                        IconButton(
                                          tooltip: 'Edit',
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.edit_outlined, size: 18),
                                          onPressed: () => showDialog(context: context, builder: (_) => StudentDialog(existing: s)),
                                        ),
                                        IconButton(
                                          tooltip: 'Remove',
                                          visualDensity: VisualDensity.compact,
                                          icon: const Icon(Icons.delete_outline, size: 18, color: C.bad),
                                          onPressed: () async {
                                            final ok = await confirm(context, 'Remove ${s.name}?', 'They will be removed from the device upload file. Their past attendance records are kept.');
                                            if (ok) app.deleteStudent(s.id);
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

class StudentDialog extends StatefulWidget {
  final Student? existing;
  const StudentDialog({super.key, this.existing});
  @override
  State<StudentDialog> createState() => _StudentDialogState();
}

class _StudentDialogState extends State<StudentDialog> {
  late final TextEditingController _id, _name, _lrn, _contact, _notes;
  int _section = 1;
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
    _id = TextEditingController(text: '${e?.id ?? context.app.nextStudentId}');
    _name = TextEditingController(text: e?.name ?? '');
    _lrn = TextEditingController(text: e?.lrn ?? '');
    _contact = TextEditingController(text: e?.contact ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _section = e?.section ?? 1;
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
      setState(() => _error = 'Enter the student\'s name.');
      return;
    }
    if (_name.text.trim().length > 24) {
      // Most devices truncate long names on screen; the file itself accepts them.
    }
    final s = (widget.existing?.copy() ?? Student(id: id, name: ''))
      ..name = _name.text.trim()
      ..section = _section
      ..authority = _authority
      ..lrn = _lrn.text.trim()
      ..contact = _contact.text.trim()
      ..notes = _notes.text.trim();
    final err = app.saveStudent(s, isNew: isNew);
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
    return AlertDialog(
      title: Text(isNew ? 'Add student' : 'Edit student', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              SizedBox(width: 110, child: TextField(controller: _id, enabled: isNew, decoration: const InputDecoration(labelText: 'Device ID'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _name, autofocus: true, decoration: const InputDecoration(labelText: 'Full name'))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _section,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Section'),
                  items: [for (var i = 1; i <= 16; i++) DropdownMenuItem(value: i, child: Text(app.sectionName(i), overflow: TextOverflow.ellipsis))],
                  onChanged: (v) => setState(() => _section = v ?? 1),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _authority,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Role on the device'),
                  items: const [DropdownMenuItem(value: 0, child: Text('Student')), DropdownMenuItem(value: 1, child: Text('Device administrator'))],
                  onChanged: (v) => setState(() => _authority = v ?? 0),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: TextField(controller: _lrn, decoration: const InputDecoration(labelText: 'LRN (optional)'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: _contact, decoration: const InputDecoration(labelText: 'Guardian contact (optional)'))),
            ]),
            const SizedBox(height: 12),
            TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(labelText: 'Notes (stays in this app, not sent to the device)')),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Align(alignment: Alignment.centerLeft, child: Text(_error!, style: const TextStyle(color: C.bad)))),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: C.muted))),
        FilledButton(onPressed: _save, child: Text(isNew ? 'Add student' : 'Save')),
      ],
    );
  }
}

class StudentDetail extends StatelessWidget {
  final Student student;
  const StudentDetail({super.key, required this.student});

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final book = app.book;
    final today = dateOnly(DateTime.now());
    final days = List.generate(30, (i) => today.subtract(Duration(days: i)));
    final rows = <DayRecord>[];
    var present = 0, late = 0, absent = 0, lateMin = 0;
    for (final d in days) {
      final r = book.recordFor(student, d);
      if (r == null) continue;
      if (r.status == DayStatus.noData || r.status == DayStatus.holiday) continue;
      rows.add(r);
      if (r.attended) present++;
      if (r.status == DayStatus.late) {
        late++;
        lateMin += r.lateMin;
      }
      if (r.status == DayStatus.absent) absent++;
    }
    final total = present + absent;
    return AlertDialog(
      title: Row(children: [
        Expanded(child: Text(student.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
        IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, size: 18)),
      ]),
      content: SizedBox(
        width: 560,
        height: 460,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('ID ${student.id} · ${app.sectionName(student.section)}${student.lrn.isEmpty ? '' : ' · LRN ${student.lrn}'}${student.contact.isEmpty ? '' : ' · ${student.contact}'}', style: const TextStyle(color: C.muted)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Kpi(label: 'Attendance', value: total == 0 ? '–' : '${(present * 100 / total).round()}%', note: 'last 30 days')),
            const SizedBox(width: 10),
            Expanded(child: Kpi(label: 'Late', value: '$late', color: C.warn, note: fmtDuration(lateMin))),
            const SizedBox(width: 10),
            Expanded(child: Kpi(label: 'Absent', value: '$absent', color: C.bad)),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: rows.isEmpty
                ? const EmptyNote('No attendance recorded in the last 30 days.')
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (c, i) {
                      final r = rows[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(children: [
                          SizedBox(width: 110, child: Text(fmtDateLong(r.date), style: const TextStyle(fontSize: 12.5))),
                          SizedBox(width: 70, child: Tag.status(r.status)),
                          const SizedBox(width: 12),
                          Text(r.in1 == null ? '' : 'in ${fmtTime(r.in1!)}', style: const TextStyle(color: C.muted)),
                          const SizedBox(width: 12),
                          Text(r.out1 == null && r.out2 == null ? (r.attended ? 'no out' : '') : 'out ${fmtTime((r.out2 ?? r.out1)!)}', style: const TextStyle(color: C.muted)),
                          const Spacer(),
                          if (r.lateMin > 0) Text('${r.lateMin} min late', style: const TextStyle(color: C.warn, fontSize: 12)),
                        ]),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

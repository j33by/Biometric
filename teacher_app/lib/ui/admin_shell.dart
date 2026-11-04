import 'package:flutter/material.dart';

import '../attendance.dart';
import '../models.dart';
import '../ph.dart';
import '../repo.dart';
import 'common.dart';

class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int _i = 0;
  static const _titles = ['Today', 'Requests', 'Teachers', 'Schedule', 'Notices'];

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[const _TodayTab(), const _RequestsTab(), const _TeachersTab(), const _ScheduleTab(), const _NoticesAdminTab()];
    return Scaffold(
      appBar: AppBar(
        title: Text('Admin · ${_titles[_i]}'),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Center(child: PhClockText(seconds: false, style: TextStyle(fontWeight: FontWeight.w700))),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'out') signOut();
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text(sb.auth.currentUser?.email ?? 'Administrator')),
              const PopupMenuItem(value: 'out', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: KeyedSubtree(key: ValueKey(_i), child: pages[_i]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (i) => setState(() => _i = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(icon: Icon(Icons.how_to_reg_outlined), selectedIcon: Icon(Icons.how_to_reg), label: 'Requests'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Teachers'),
          NavigationDestination(icon: Icon(Icons.schedule_outlined), selectedIcon: Icon(Icons.schedule), label: 'Schedule'),
          NavigationDestination(icon: Icon(Icons.campaign_outlined), selectedIcon: Icon(Icons.campaign), label: 'Notices'),
        ],
      ),
    );
  }
}

// ================================================================= Today
/// Who is in school: every teacher's duty for the chosen day (Philippine date), with their
/// log-in / log-out and status. Same maths as the desktop app (schedule_calc.dart).
class _TodayTab extends StatefulWidget {
  const _TodayTab();
  @override
  State<_TodayTab> createState() => _TodayTabState();
}

class _TodayTabState extends State<_TodayTab> {
  DateTime _day = phToday();
  late Future<AdminDay> _f = Repo.adminDay(_day);

  void _load() => setState(() => _f = Repo.adminDay(_day));

  void _go(int delta) {
    _day = _day.add(Duration(days: delta));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isToday = _day == phToday();
    return RefreshIndicator(
      onRefresh: () async {
        _load();
        try {
          await _f;
        } catch (_) {}
      },
      child: Busy<AdminDay>(
        future: _f,
        builder: (data) => Ticker(
          builder: (context, now) {
            final rows = [for (final t in data.teachers) (t, data.viewOf(t, now))];
            final duty = rows.where((r) => r.$2.state != DayState.off).toList()
              ..sort((a, b) {
                final x = a.$2.shift?.times.startMin ?? 9999, y = b.$2.shift?.times.startMin ?? 9999;
                return x != y ? x.compareTo(y) : a.$1.name.compareTo(b.$1.name);
              });
            final off = rows.where((r) => r.$2.state == DayState.off).toList();
            int n(bool Function(DayView) f) => duty.where((r) => f(r.$2)).length;
            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _go(-1)),
                TextButton(onPressed: isToday ? null : () {
                  _day = phToday();
                  _load();
                }, child: Text(isToday ? 'Today · ${fDay.format(_day)}' : '${fDay.format(_day)} · back to today')),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _go(1)),
              ]),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  _stat(context, 'Present', n((v) => v.attended), stateColor(DayState.present)),
                  _stat(context, 'Late', n((v) => v.state == DayState.late), stateColor(DayState.late)),
                  _stat(context, 'Absent', n((v) => v.state == DayState.absent), stateColor(DayState.absent)),
                  _stat(context, 'On leave', n((v) => v.state == DayState.leave), stateColor(DayState.leave)),
                ]),
              ),
              if (!data.hasData)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Text('No device punches for this day yet. The school has not downloaded the device, so nobody can be marked absent.', style: TextStyle(color: cs.outline, fontSize: 12)),
                ),
              if (duty.isEmpty) const Empty(Icons.event_available, 'Nobody has duty on this day.'),
              for (final r in duty)
                ListTile(
                  title: Text(r.$1.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${r.$2.schedule}${r.$2.inTime == null ? '' : '\n${inOut(r.$2)}'}'),
                  isThreeLine: r.$2.inTime != null,
                  trailing: StateChip(r.$2.state, text: r.$2.state == DayState.late ? '${r.$2.lateMin} min late' : null),
                ),
              if (off.isNotEmpty)
                ExpansionTile(
                  title: Text('No class (${off.length})', style: TextStyle(color: cs.outline)),
                  children: [for (final r in off) ListTile(dense: true, title: Text(r.$1.name))],
                ),
            ]);
          },
        ),
      ),
    );
  }

  String inOut(DayView v) {
    final out = v.outTime;
    return 'In ${fTime.format(v.inTime!)}${out == null ? ' · no Out yet' : ' · Out ${fTime.format(out)}'}';
  }

  Widget _stat(BuildContext context, String label, int value, Color color) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(children: [
              Text('$value', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color)),
              Text(label, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
            ]),
          ),
        ),
      );
}

// ================================================================= Requests
class _RequestsTab extends StatefulWidget {
  const _RequestsTab();
  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  String _status = 'pending';
  late Future<List<Link>> _f = Repo.links(_status);

  void _load() => setState(() => _f = Repo.links(_status));

  Future<void> _act(Link l, String status, {String? note}) async {
    try {
      await Repo.review(l.id, status, note: note);
      if (mounted) toast(context, status == 'approved' ? 'Approved ${l.displayName}' : 'Updated ${l.displayName}');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    _load();
  }

  Future<void> _unlink(Link l, bool approve) async {
    String note = '';
    if (!approve) {
      final n = await askText(context, title: 'Keep linked', label: 'Reason (shown to the teacher, optional)');
      if (n == null) return;
      note = n.trim();
    }
    try {
      await Repo.resolveUnlink(l.id, approve, note: note);
      if (mounted) toast(context, approve ? 'Unlinked ${l.displayName}' : 'Kept ${l.displayName} linked');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    _load();
  }

  Future<void> _deny(Link l) async {
    final note = await askText(context, title: 'Deny request', label: 'Reason (shown to the teacher, optional)');
    if (note == null) return;
    await _act(l, 'denied', note: note.trim());
  }

  Future<void> _edit(Link l) async {
    final r = await showDialog<_EditResult>(context: context, builder: (_) => _EditLinkDialog(link: l));
    if (r == null) return;
    try {
      await Repo.review(l.id, l.status, teacherId: r.teacherId, accountName: r.accountName, note: r.note);
      if (r.renameTo != null) {
        await Repo.renameTeacher(r.teacherId, r.renameTo!);
      }
      if (mounted) toast(context, 'Saved');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'pending', label: Text('Pending')),
              ButtonSegment(value: 'approved', label: Text('Approved')),
              ButtonSegment(value: 'denied', label: Text('Denied')),
              ButtonSegment(value: 'unlink', label: Text('Unlink')),
            ],
            showSelectedIcon: false,
            selected: {_status},
            onSelectionChanged: (s) {
              _status = s.first;
              _load();
            },
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              _load();
              try {
                await _f;
              } catch (_) {}
            },
            child: Busy<List<Link>>(
              future: _f,
              builder: (rows) => rows.isEmpty
                  ? ListView(children: [Empty(Icons.inbox_outlined, 'No $_status requests.')])
                  : ListView(children: [for (final l in rows) _card(l)]),
            ),
          ),
        ),
      ]);

  Widget _card(Link l) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(l.displayName.isEmpty ? '(no name)' : l.displayName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
              IconButton(tooltip: 'Edit', icon: const Icon(Icons.edit_outlined), onPressed: () => _edit(l)),
            ]),
            Text(l.email, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.link, size: 18),
              const SizedBox(width: 6),
              Expanded(child: Text('Bound to: ${l.teacherName.isEmpty ? '(unknown)' : l.teacherName}  ·  ID ${l.teacherId}')),
            ]),
            if (l.unlinkRequested)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Unlink requested${l.unlinkReason.isEmpty ? '' : ': ${l.unlinkReason}'}', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
              ),
            if (l.adminNote.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Note: ${l.adminNote}')),
            Text('Requested ${fStamp.format(l.createdAt)}', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              if (_status == 'unlink') ...[
                FilledButton.icon(onPressed: () => _unlink(l, true), icon: const Icon(Icons.link_off), label: const Text('Approve unlink')),
                OutlinedButton.icon(onPressed: () => _unlink(l, false), icon: const Icon(Icons.close), label: const Text('Keep linked')),
              ] else ...[
                if (l.status != 'approved') FilledButton.icon(onPressed: () => _act(l, 'approved'), icon: const Icon(Icons.check), label: const Text('Approve')),
                if (l.status != 'denied') OutlinedButton.icon(onPressed: () => _deny(l), icon: const Icon(Icons.close), label: Text(l.status == 'approved' ? 'Revoke' : 'Deny')),
              ],
            ]),
          ]),
        ),
      );
}

class _EditResult {
  final int teacherId;
  final String accountName;
  final String note;
  final String? renameTo; // new name for the teacher record itself, if changed
  _EditResult(this.teacherId, this.accountName, this.note, this.renameTo);
}

/// Admin can change: the account's display name, which teacher record it is bound to,
/// the teacher record's own name, and the note.
class _EditLinkDialog extends StatefulWidget {
  final Link link;
  const _EditLinkDialog({required this.link});
  @override
  State<_EditLinkDialog> createState() => _EditLinkDialogState();
}

class _EditLinkDialogState extends State<_EditLinkDialog> {
  late final _account = TextEditingController(text: widget.link.accountName);
  late final _teacher = TextEditingController(text: widget.link.teacherName);
  late final _note = TextEditingController(text: widget.link.adminNote);
  late int _teacherId = widget.link.teacherId;
  late String _origName = widget.link.teacherName;

  Future<void> _rebind() async {
    final s = await showDialog<TeacherRow>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Bind to a different teacher'),
        content: SizedBox(width: 420, height: 420, child: TeacherPicker(search: Repo.teachers, loadOnStart: true, onPick: (s) => Navigator.pop(c, s))),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel'))],
      ),
    );
    if (s == null) return;
    setState(() {
      _teacherId = s.id;
      _teacher.text = s.name;
      _origName = s.name;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Edit request'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: _account, decoration: const InputDecoration(labelText: 'Name shown on the account')),
              const SizedBox(height: 12),
              TextField(controller: _teacher, decoration: InputDecoration(labelText: 'Teacher record name (ID $_teacherId)', helperText: 'Renames the biometric record itself')),
              Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: _rebind, icon: const Icon(Icons.swap_horiz), label: const Text('Bind to a different teacher'))),
              TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note to the teacher (optional)')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final newName = _teacher.text.trim();
              Navigator.pop(context, _EditResult(_teacherId, _account.text.trim(), _note.text.trim(), newName.isNotEmpty && newName != _origName ? newName : null));
            },
            child: const Text('Save'),
          ),
        ],
      );
}

// ================================================================= Teachers
class _TeachersTab extends StatefulWidget {
  const _TeachersTab();
  @override
  State<_TeachersTab> createState() => _TeachersTabState();
}

class _TeachersTabState extends State<_TeachersTab> {
  Key _k = UniqueKey();

  Future<void> _rename(TeacherRow s) async {
    final name = await askText(context, title: 'Rename teacher (ID ${s.id})', label: 'Name', initial: s.name);
    if (name == null || name.trim().isEmpty || name.trim() == s.name) return;
    try {
      await Repo.renameTeacher(s.id, name);
      if (mounted) toast(context, 'Renamed. The desktop app will pick this up on its next sync.');
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    setState(() => _k = UniqueKey());
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: TeacherPicker(key: _k, search: Repo.teachers, loadOnStart: true, onPick: _rename),
      );
}

// ================================================================= Schedule
/// Faculty slots (subject + weekly shifts) and the shift times, in Philippine time.
/// Editing a shift here updates the database; the desktop app downloads it on its next
/// sync and rewrites Employee Form.xls for the biometric device.
class _ScheduleTab extends StatefulWidget {
  const _ScheduleTab();
  @override
  State<_ScheduleTab> createState() => _ScheduleTabState();
}

class _ScheduleData {
  final List<FacultyRow> faculty;
  final List<ShiftRow> shifts;
  final List<TeacherRow> teachers;
  const _ScheduleData(this.faculty, this.shifts, this.teachers);
}

class _ScheduleTabState extends State<_ScheduleTab> {
  late Future<_ScheduleData> _f = _load();

  Future<_ScheduleData> _load() async {
    final r = await Future.wait([Repo.allFaculty(), Repo.allShifts(), Repo.teachers('')]);
    return _ScheduleData(r[0] as List<FacultyRow>, r[1] as List<ShiftRow>, r[2] as List<TeacherRow>);
  }

  void _reload() => setState(() => _f = _load());

  Future<void> _edit(ShiftRow s) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _ShiftDialog(shift: s));
    if (saved == true) {
      if (mounted) toast(context, 'Shift ${s.no} saved. The desktop app will pick it up on its next sync.');
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const days = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        try {
          await _f;
        } catch (_) {}
      },
      child: Busy<_ScheduleData>(
        future: _f,
        builder: (d) {
          final shifts = {for (final s in d.shifts) s.no: s};
          final named = d.faculty.where((f) => f.name.trim().isNotEmpty || f.week.any((x) => x != 0)).toList();
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.public, size: 18),
                const SizedBox(width: 8),
                const Expanded(child: Text('All times are Philippine time (UTC+8). The biometric device reads the same clock.', style: TextStyle(fontSize: 12.5))),
                const SizedBox(width: 8),
                const PhClockText(seconds: false, style: TextStyle(fontWeight: FontWeight.w800)),
              ]),
            ),
            const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text('Shifts', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            for (final s in d.shifts)
              ListTile(
                dense: true,
                leading: CircleAvatar(radius: 14, child: Text('${s.no}', style: const TextStyle(fontSize: 12))),
                title: Text(s.isEmpty ? 'Not used' : s.label, style: TextStyle(fontWeight: FontWeight.w600, color: s.isEmpty ? cs.outline : null)),
                subtitle: s.isEmpty ? null : Text('${s.in1} – ${s.out1} (24-hour)'),
                trailing: const Icon(Icons.edit_outlined, size: 18),
                onTap: () => _edit(s),
              ),
            const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 4), child: Text('Faculty schedules', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            if (named.isEmpty) const Empty(Icons.schedule, 'No faculty schedules yet. Set them up in the desktop app.'),
            for (final f in named)
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(f.name.isEmpty ? 'Faculty ${f.no}' : f.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(d.teachers.where((t) => t.faculty == f.no).map((t) => t.name).join(', ').ifEmpty('No teacher assigned'), style: TextStyle(color: cs.outline, fontSize: 12)),
                    const SizedBox(height: 6),
                    for (var i = 1; i <= 5; i++)
                      if (f.week[i] != 0)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Row(children: [
                            SizedBox(width: 40, child: Text(days[i], style: TextStyle(color: cs.outline))),
                            Text(shifts[f.week[i]]?.label ?? 'Shift ${f.week[i]}', style: const TextStyle(fontWeight: FontWeight.w600)),
                          ]),
                        ),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

/// Edit one shift. Type "7:50 AM", "1:00 PM" or "13:00", or tap the clock; the database always
/// gets 24-hour "HH:mm". Nothing here depends on the phone's time zone.
class _ShiftDialog extends StatefulWidget {
  final ShiftRow shift;
  const _ShiftDialog({required this.shift});
  @override
  State<_ShiftDialog> createState() => _ShiftDialogState();
}

class _ShiftDialogState extends State<_ShiftDialog> {
  static const _keys = ['in1', 'out1', 'in2', 'out2', 'otIn', 'otOut'];
  late final Map<String, TextEditingController> _c = {
    'in1': TextEditingController(text: _show(widget.shift.in1)),
    'out1': TextEditingController(text: _show(widget.shift.out1)),
    'in2': TextEditingController(text: _show(widget.shift.in2)),
    'out2': TextEditingController(text: _show(widget.shift.out2)),
    'otIn': TextEditingController(text: _show(widget.shift.otIn)),
    'otOut': TextEditingController(text: _show(widget.shift.otOut)),
  };
  String? _error;
  String? _warning;
  bool _ack = false;
  bool _busy = false;

  String _show(String v) {
    final m = parseHm(v);
    return m == null ? '' : fmtHm12(m);
  }

  Future<void> _pick(String key) async {
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
      _ack = false;
      _warning = null;
    });
  }

  Widget _field(String key, String label) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 6, bottom: 8),
          child: TextField(
            controller: _c[key],
            onChanged: (_) => setState(() {
              _ack = false;
              _warning = null;
            }),
            decoration: InputDecoration(
              labelText: label,
              hintText: '7:50 AM',
              isDense: true,
              helperText: _helper(key),
              suffixIcon: IconButton(icon: const Icon(Icons.access_time, size: 18), onPressed: () => _pick(key)),
            ),
          ),
        ),
      );

  String _helper(String k) {
    final t = _c[k]!.text.trim();
    if (t.isEmpty) return ' ';
    final n = normalizeTimeInput(t);
    return n == null ? 'not a time' : '→ $n';
  }

  Future<void> _save() async {
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
    for (final p in [('in1', 'out1', 'Period 1'), ('in2', 'out2', 'Period 2'), ('otIn', 'otOut', 'Overtime')]) {
      final a = v[p.$1]!, b = v[p.$2]!;
      if (a.isEmpty != b.isEmpty) {
        setState(() => _error = '${p.$3}: give both the log-in and the log-out time, or leave both empty.');
        return;
      }
      if (a.isNotEmpty && parseHm(b)! <= parseHm(a)!) {
        setState(() => _error = '${p.$3}: the log-out time must be later than the log-in time.');
        return;
      }
    }
    if (v['in2']!.isNotEmpty && (v['in1']!.isEmpty || parseHm(v['in2']!)! < parseHm(v['out1']!)!)) {
      setState(() => _error = 'Period 2 must start after Period 1 ends.');
      return;
    }
    // "1:00" typed for 1 PM would be saved as 1 AM: ask once before accepting odd hours
    final odd = <String>[];
    for (final k in ['in1', 'out1', 'in2', 'out2']) {
      final m = v[k]!.isEmpty ? null : parseHm(v[k]!);
      if (m != null && (m < 5 * 60 || m > 21 * 60)) odd.add(fmtHm12(m));
    }
    if (odd.isNotEmpty && !_ack) {
      setState(() {
        _error = null;
        _warning = '${odd.join(', ')} is outside normal school hours. If you meant PM, type it as 1:00 PM. Press Save again to keep it.';
        _ack = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Repo.saveShift(widget.shift.no, v['in1']!, v['out1']!, v['in2']!, v['out2']!, v['otIn']!, v['otOut']!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Shift ${widget.shift.no} · Philippine time'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Type 7:50 AM, 1:00 PM or 13:00. Leave a period empty if it is not used.', style: TextStyle(fontSize: 12.5)),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [_field('in1', 'Log in'), _field('out1', 'Log out')]),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [_field('in2', 'Period 2 in'), _field('out2', 'Period 2 out')]),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [_field('otIn', 'Overtime in'), _field('otOut', 'Overtime out')]),
            if (_warning != null) Text(_warning!, style: const TextStyle(color: Color(0xFFEF6C00), fontSize: 12.5)),
            if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          ]),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: _busy ? null : _save, child: Text(_ack ? 'Save anyway' : 'Save')),
        ],
      );
}

// ================================================================= Notices
class _NoticesAdminTab extends StatefulWidget {
  const _NoticesAdminTab();
  @override
  State<_NoticesAdminTab> createState() => _NoticesAdminTabState();
}

class _NoticesAdminTabState extends State<_NoticesAdminTab> {
  late Future<List<Notice>> _f = Repo.notices();
  void _load() => setState(() => _f = Repo.notices());

  Future<void> _add() async {
    final title = TextEditingController();
    final body = TextEditingController();
    bool pinned = false;
    int? faculty;
    final names = await Repo.facultyNames();
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setS) => AlertDialog(
          title: const Text('New notice'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 10),
              TextField(controller: body, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'Details')),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: faculty,
                decoration: const InputDecoration(labelText: 'Audience'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All teachers')),
                  for (var i = 1; i <= 16; i++) DropdownMenuItem<int?>(value: i, child: Text((names[i] ?? '').isEmpty ? 'Faculty $i' : names[i]!)),
                ],
                onChanged: (v) => setS(() => faculty = v),
              ),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Pin to top'), value: pinned, onChanged: (v) => setS(() => pinned = v)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Post')),
          ],
        ),
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return;
    try {
      await Repo.addNotice(title.text.trim(), body.text.trim(), faculty: faculty, pinned: pinned);
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    _load();
  }

  Future<void> _delete(Notice n) async {
    try {
      await Repo.deleteNotice(n.id);
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    }
    _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        floatingActionButton: FloatingActionButton.extended(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Notice')),
        body: RefreshIndicator(
          onRefresh: () async {
            _load();
            try {
              await _f;
            } catch (_) {}
          },
          child: Busy<List<Notice>>(
            future: _f,
            builder: (ns) => ns.isEmpty
                ? ListView(children: const [Empty(Icons.campaign_outlined, 'No notices yet. Tap + to post one.')])
                : ListView(padding: const EdgeInsets.only(bottom: 80), children: [
                    for (final n in ns) NoticeTile(n, trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _delete(n))),
                  ]),
          ),
        ),
      );
}

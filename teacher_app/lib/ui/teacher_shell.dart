import 'package:flutter/material.dart';

import '../attendance.dart';
import '../models.dart';
import '../ph.dart';
import '../repo.dart';
import 'common.dart';

/// Everything a linked teacher sees. All dates and times are Philippine time.
class TeacherShell extends StatefulWidget {
  final Link link;
  final VoidCallback onReload;
  const TeacherShell({super.key, required this.link, required this.onReload});
  @override
  State<TeacherShell> createState() => _TeacherShellState();
}

class _TeacherShellState extends State<TeacherShell> {
  int _i = 0;
  static const _titles = ['Home', 'My attendance', 'My logs', 'Notices', 'Profile'];
  late Future<MySchedule> _schedule = Repo.mySchedule(widget.link);

  void _reloadSchedule() => setState(() => _schedule = Repo.mySchedule(widget.link));

  @override
  Widget build(BuildContext context) {
    final l = widget.link;
    final pages = <Widget>[
      HomeTab(link: l, schedule: _schedule, goTo: (i) => setState(() => _i = i), onRefresh: _reloadSchedule),
      AttendanceTab(link: l, schedule: _schedule),
      LogsTab(link: l, schedule: _schedule),
      const NoticesTab(),
      ProfileTab(link: l, onReload: widget.onReload),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_i]),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                const PhClockText(seconds: false, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text('Philippine time', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline)),
              ]),
            ),
          ),
        ],
      ),
      body: KeyedSubtree(key: ValueKey(_i), child: pages[_i]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: (i) => setState(() => _i = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Attendance'),
          NavigationDestination(icon: Icon(Icons.fingerprint), label: 'Logs'),
          NavigationDestination(icon: Icon(Icons.campaign_outlined), selectedIcon: Icon(Icons.campaign), label: 'Notices'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

/// Punches grouped by calendar day (ascending inside each day).
Map<DateTime, List<DateTime>> groupByDay(List<DateTime> logs) {
  final m = <DateTime, List<DateTime>>{};
  for (final t in logs) {
    m.putIfAbsent(dayOf(t), () => []).add(t);
  }
  for (final v in m.values) {
    v.sort();
  }
  return m;
}

/// "In 7:48 AM · Out 9:52 AM"
String inOutText(DayView v) {
  if (v.inTime == null) return v.schedule.isEmpty ? '' : 'Scheduled ${v.schedule}';
  final out = v.outTime;
  return 'In ${fTime.format(v.inTime!)}${out == null ? ' · no Out yet' : ' · Out ${fTime.format(out)}'}';
}

// ================================================================= Home
class HomeTab extends StatefulWidget {
  final Link link;
  final Future<MySchedule> schedule;
  final void Function(int) goTo;
  final VoidCallback onRefresh;
  const HomeTab({super.key, required this.link, required this.schedule, required this.goTo, required this.onRefresh});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late Future<List<DateTime>> _today = _loadToday();
  late Future<Set<DateTime>> _logged = _loadLogged();
  late Future<List<Notice>> _notices = Repo.notices(limit: 3);

  Future<List<DateTime>> _loadToday() {
    final d = phToday();
    return Repo.logs(widget.link.teacherId, d, d.add(const Duration(days: 1)));
  }

  Future<Set<DateTime>> _loadLogged() {
    final d = phToday();
    return Repo.loggedDays(d, d);
  }

  Future<void> _reload() async {
    widget.onRefresh();
    setState(() {
      _today = _loadToday();
      _logged = _loadLogged();
      _notices = Repo.notices(limit: 3);
    });
    try {
      await _today;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.link;
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            ClipOval(child: Image.asset('assets/images/cnhs_logo.png', width: 52, height: 52, fit: BoxFit.cover)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Hello, ${l.displayName}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Row(children: [Flexible(child: FacultyName(l.faculty)), if (l.position.isNotEmpty) Text(' · ${l.position}')]),
                if (l.teacherNo.isNotEmpty) Text('Teacher ID ${l.teacherNo}', style: TextStyle(color: cs.onPrimaryContainer.withValues(alpha: 0.75), fontSize: 12)),
              ]),
            ),
          ]),
        ),
        Busy<MySchedule>(
          future: widget.schedule,
          builder: (sch) => Column(children: [
            _todayCard(context, sch),
            _weekCard(context, sch),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 8, 4),
          child: Row(children: [
            const Text('Latest notices', style: TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            TextButton(onPressed: () => widget.goTo(3), child: const Text('See all')),
          ]),
        ),
        Busy<List<Notice>>(
          future: _notices,
          builder: (ns) => ns.isEmpty ? const Empty(Icons.campaign_outlined, 'No notices yet.') : Column(children: [for (final n in ns) NoticeTile(n)]),
        ),
      ]),
    );
  }

  Widget _todayCard(BuildContext context, MySchedule sch) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Busy<List<DateTime>>(
          future: _today,
          builder: (punches) => Busy<Set<DateTime>>(
            future: _logged,
            builder: (logged) => Ticker(
              builder: (context, now) {
                final today = dayOf(now);
                final v = sch.view(today, punches.where((p) => dayOf(p) == today).toList(), logged.contains(today), now);
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('Today · ${fDay.format(today)}', style: const TextStyle(fontWeight: FontWeight.w600))),
                    StateChip(v.state),
                  ]),
                  const SizedBox(height: 10),
                  if (v.schedule.isNotEmpty) ...[
                    Text('You must be in school', style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 12)),
                    Text(v.schedule, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    if (sch.subject.isNotEmpty) Text(sch.subject, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  ] else
                    Text(v.state == DayState.leave ? 'On leave' : 'No class today', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 10),
                  Text(nextStep(v, now, sch.rules), style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (v.punches.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      _timeBox(context, 'Log in', v.inTime == null ? '–' : fTime.format(v.inTime!), v.state == DayState.late ? '${v.lateMin} min late' : null),
                      const SizedBox(width: 10),
                      _timeBox(context, 'Log out', v.outTime == null ? '–' : fTime.format(v.outTime!), v.earlyMin > 0 ? '${v.earlyMin} min early' : null),
                    ]),
                  ],
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeBox(BuildContext context, String label, String value, String? note) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: cs.outline, fontSize: 12)),
          Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (note != null) Text(note, style: const TextStyle(color: Color(0xFFEF6C00), fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  /// This week's log-in / log-out times, one row per weekday.
  Widget _weekCard(BuildContext context, MySchedule sch) {
    final f = sch.faculty;
    if (f == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final today = phToday();
    const names = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
    final days = [1, 2, 3, 4, 5, if (f.week[6] != 0) 6, if (f.week[0] != 0) 0];
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('My weekly schedule', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          for (final d in days)
            Container(
              margin: const EdgeInsets.symmetric(vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: today.weekday % 7 == d ? cs.primaryContainer : null,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                SizedBox(width: 96, child: Text(names[d], style: TextStyle(fontWeight: today.weekday % 7 == d ? FontWeight.w800 : FontWeight.w500))),
                Expanded(
                  child: Text(
                    f.week[d] == 0 ? 'No class' : (sch.shifts[f.week[d]]?.label ?? '–'),
                    style: TextStyle(color: f.week[d] == 0 ? cs.outline : null, fontWeight: f.week[d] == 0 ? FontWeight.normal : FontWeight.w600),
                  ),
                ),
              ]),
            ),
        ]),
      ),
    );
  }
}

// ================================================================= Attendance
class AttendanceTab extends StatefulWidget {
  final Link link;
  final Future<MySchedule> schedule;
  const AttendanceTab({super.key, required this.link, required this.schedule});
  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceData {
  final List<DateTime> logs;
  final Set<DateTime> logged;
  final MySchedule schedule;
  const _AttendanceData(this.logs, this.logged, this.schedule);
}

class _AttendanceTabState extends State<AttendanceTab> {
  DateTime _month = DateTime(phToday().year, phToday().month);
  late Future<_AttendanceData> _f = _load();

  Future<_AttendanceData> _load() async {
    final end = DateTime(_month.year, _month.month + 1);
    final r = await Future.wait([
      Repo.logs(widget.link.teacherId, _month, end),
      Repo.loggedDays(_month, end.subtract(const Duration(days: 1))),
      widget.schedule,
    ]);
    return _AttendanceData(r[0] as List<DateTime>, r[1] as Set<DateTime>, r[2] as MySchedule);
  }

  void _go(int delta) => setState(() {
        _month = DateTime(_month.year, _month.month + delta);
        _f = _load();
      });

  Future<void> _reload() async {
    setState(() => _f = _load());
    try {
      await _f;
    } catch (_) {}
  }

  void _showDay(DayView d) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(fDay.format(d.day), style: Theme.of(context).textTheme.titleLarge)), StateChip(d.state)]),
          const SizedBox(height: 6),
          if (d.schedule.isNotEmpty) Text('Scheduled ${d.schedule}'),
          if (d.leaveType != null) Text(d.leaveType!),
          const SizedBox(height: 4),
          Text(inOutText(d)),
          if (d.lateMin > 0) Text('${d.lateMin} min late', style: const TextStyle(color: Color(0xFFEF6C00), fontWeight: FontWeight.w600)),
          if (d.earlyMin > 0) Text('Left ${d.earlyMin} min before the end', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 4, children: [for (final t in d.punches) Chip(label: Text(fTime.format(t)))]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = phNow();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _go(-1)),
          Text(fMonth.format(_month), style: Theme.of(context).textTheme.titleMedium),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: isCurrent ? null : () => _go(1)),
        ]),
        Busy<_AttendanceData>(
          future: _f,
          builder: (data) {
            final byDay = groupByDay(data.logs);
            final count = DateTime(_month.year, _month.month + 1, 0).day;
            final views = <DateTime, DayView>{
              for (var d = 1; d <= count; d++)
                DateTime(_month.year, _month.month, d):
                    data.schedule.view(DateTime(_month.year, _month.month, d), byDay[DateTime(_month.year, _month.month, d)] ?? const [], data.logged.contains(DateTime(_month.year, _month.month, d)), now),
            };
            final list = views.values.toList();
            int n(DayState s) => list.where((v) => v.state == s).length;
            final lateMin = list.fold<int>(0, (a, v) => a + v.lateMin);
            final first = DateTime(_month.year, _month.month, 1);
            final offset = first.weekday % 7; // Sunday first
            final cells = <Widget>[
              for (final w in 'SMTWTFS'.split('')) Center(child: Text(w, style: TextStyle(color: cs.outline, fontWeight: FontWeight.w600))),
              for (var i = 0; i < offset; i++) const SizedBox.shrink(),
              for (final v in list) _cell(v, cs, now),
            ];
            final shown = list.where((v) => v.state != DayState.off && v.state != DayState.noData && v.state != DayState.upcoming).toList()
              ..sort((a, b) => b.day.compareTo(a.day));
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  _stat('Present', '${n(DayState.present) + n(DayState.late)}', cs, color: stateColor(DayState.present)),
                  _stat('Late', '${n(DayState.late)}', cs, color: stateColor(DayState.late)),
                  _stat('Absent', '${n(DayState.absent)}', cs, color: stateColor(DayState.absent)),
                  _stat('On leave', '${n(DayState.leave)}', cs, color: stateColor(DayState.leave)),
                ]),
              ),
              if (lateMin > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Total late this month: ${fmtMinutes(lateMin)}', style: TextStyle(color: cs.outline))),
              Padding(
                padding: const EdgeInsets.all(12),
                child: GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 4, crossAxisSpacing: 4, children: cells),
              ),
              if (shown.isEmpty) const Empty(Icons.event_busy, 'No attendance recorded this month.'),
              for (final v in shown)
                ListTile(
                  leading: Icon(_icon(v.state), color: stateColor(v.state)),
                  title: Text(fDay.format(v.day)),
                  subtitle: Text(v.attended ? '${v.schedule}\n${inOutText(v)}' : (v.state == DayState.leave ? '${v.leaveType ?? 'Leave'} · ${v.schedule}' : v.schedule)),
                  isThreeLine: v.attended,
                  trailing: StateChip(v.state, text: v.state == DayState.late ? '${v.lateMin} min late' : null),
                  onTap: () => _showDay(v),
                ),
            ]);
          },
        ),
      ]),
    );
  }

  IconData _icon(DayState s) {
    switch (s) {
      case DayState.present:
        return Icons.check_circle;
      case DayState.late:
        return Icons.watch_later;
      case DayState.absent:
        return Icons.cancel;
      case DayState.leave:
        return Icons.event_busy;
      default:
        return Icons.schedule;
    }
  }

  Widget _stat(String label, String value, ColorScheme cs, {required Color color}) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color)),
              Text(label, style: TextStyle(color: cs.outline, fontSize: 12)),
            ]),
          ),
        ),
      );

  Widget _cell(DayView v, ColorScheme cs, DateTime now) {
    final show = v.state != DayState.off && v.state != DayState.noData && v.state != DayState.upcoming;
    final c = stateColor(v.state);
    final today = dayOf(now) == v.day;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: show ? () => _showDay(v) : null,
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: show ? c.withValues(alpha: 0.16) : null,
          borderRadius: BorderRadius.circular(8),
          border: today ? Border.all(color: cs.primary, width: 2) : null,
        ),
        child: Text('${v.day.day}', style: TextStyle(fontWeight: show ? FontWeight.w700 : FontWeight.normal, color: show ? c : cs.outline)),
      ),
    );
  }
}

// ================================================================= Logs
class LogsTab extends StatefulWidget {
  final Link link;
  final Future<MySchedule> schedule;
  const LogsTab({super.key, required this.link, required this.schedule});
  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsData {
  final List<DateTime> logs;
  final Set<DateTime> logged;
  final MySchedule schedule;
  const _LogsData(this.logs, this.logged, this.schedule);
}

class _LogsTabState extends State<LogsTab> {
  int _days = 30;
  late Future<_LogsData> _f = _load();

  Future<_LogsData> _load() async {
    final end = phToday();
    final from = end.subtract(Duration(days: _days));
    final r = await Future.wait([
      Repo.logs(widget.link.teacherId, from, end.add(const Duration(days: 1))),
      Repo.loggedDays(from, end),
      widget.schedule,
    ]);
    return _LogsData(r[0] as List<DateTime>, r[1] as Set<DateTime>, r[2] as MySchedule);
  }

  Future<void> _reload() async {
    setState(() => _f = _load());
    try {
      await _f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _reload,
      child: Busy<_LogsData>(
        future: _f,
        builder: (data) {
          final now = phNow();
          final byDay = groupByDay(data.logs);
          // every day that has punches, plus duty days with none (absent / leave) so gaps are visible
          final days = <DateTime>{...byDay.keys};
          final end = dayOf(now);
          for (var i = 0; i <= _days; i++) {
            final d = end.subtract(Duration(days: i));
            final v = data.schedule.view(d, byDay[d] ?? const [], data.logged.contains(d), now);
            if (v.state == DayState.absent || v.state == DayState.leave) days.add(d);
          }
          final sorted = days.toList()..sort((a, b) => b.compareTo(a));
          return ListView(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: SegmentedButton<int>(
                showSelectedIcon: false,
                segments: const [ButtonSegment(value: 14, label: Text('14 days')), ButtonSegment(value: 30, label: Text('30 days')), ButtonSegment(value: 60, label: Text('60 days'))],
                selected: {_days},
                onSelectionChanged: (s) {
                  _days = s.first;
                  _reload();
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text('Your own log-ins and log-outs from the biometric device. They appear after the school downloads the device.', style: TextStyle(color: cs.outline, fontSize: 12)),
            ),
            if (sorted.isEmpty) const Empty(Icons.fingerprint, 'No punches in this period.'),
            for (final d in sorted) _dayBlock(context, d, data, byDay[d] ?? const [], now),
          ]);
        },
      ),
    );
  }

  Widget _dayBlock(BuildContext context, DateTime d, _LogsData data, List<DateTime> punches, DateTime now) {
    final cs = Theme.of(context).colorScheme;
    final v = data.schedule.view(d, punches, data.logged.contains(d), now);
    final p = v.punches;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(fDay.format(d), style: const TextStyle(fontWeight: FontWeight.w700))),
            StateChip(v.state, text: v.state == DayState.late ? '${v.lateMin} min late' : null),
          ]),
          if (v.schedule.isNotEmpty) Text('Scheduled ${v.schedule}', style: TextStyle(color: cs.outline, fontSize: 12)),
          if (v.leaveType != null) Text(v.leaveType!, style: TextStyle(color: cs.outline, fontSize: 12)),
          const SizedBox(height: 6),
          for (var i = 0; i < p.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(Icons.fingerprint, size: 18, color: cs.outline),
                const SizedBox(width: 8),
                Text(fTime.format(p[i]), style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(_label(v, p[i], i, p.length), style: TextStyle(color: cs.outline, fontSize: 12)),
              ]),
            ),
          if (v.missedOut) const Padding(padding: EdgeInsets.only(top: 4), child: Text('No log-out recorded', style: TextStyle(color: Color(0xFFEF6C00), fontSize: 12, fontWeight: FontWeight.w600))),
          if (v.earlyMin > 0) Padding(padding: const EdgeInsets.only(top: 4), child: Text('Left ${v.earlyMin} min before the end', style: TextStyle(color: cs.outline, fontSize: 12))),
        ]),
      ),
    );
  }

  String _label(DayView v, DateTime t, int i, int n) {
    if (v.inTime == t) return 'Log in';
    if (v.outTime == t) return 'Log out';
    return i == 0 ? 'First' : (i == n - 1 ? 'Last' : '');
  }
}

// ================================================================= Notices
class NoticesTab extends StatefulWidget {
  const NoticesTab({super.key});
  @override
  State<NoticesTab> createState() => _NoticesTabState();
}

class _NoticesTabState extends State<NoticesTab> {
  late Future<List<Notice>> _f = Repo.notices();
  Future<void> _reload() async {
    setState(() => _f = Repo.notices());
    try {
      await _f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _reload,
        child: Busy<List<Notice>>(
          future: _f,
          builder: (ns) => ns.isEmpty
              ? ListView(children: const [Empty(Icons.campaign_outlined, 'No notices yet.')])
              : ListView(children: [for (final n in ns) NoticeTile(n)]),
        ),
      );
}

// ================================================================= Profile
class ProfileTab extends StatelessWidget {
  final Link link;
  final VoidCallback onReload;
  const ProfileTab({super.key, required this.link, required this.onReload});

  Future<void> _run(BuildContext context, Future<void> Function() job, String done) async {
    try {
      await job();
      if (context.mounted) toast(context, done);
      onReload();
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    }
  }

  Future<void> _requestUnlink(BuildContext context) async {
    final reason = await askText(context, title: 'Request unlink', label: 'Why? (e.g. wrong record, new account)', lines: 2);
    if (reason == null || !context.mounted) return;
    await _run(context, () => Repo.requestUnlink(reason), 'Unlink request sent to the admin.');
  }

  @override
  Widget build(BuildContext context) => ListView(children: [
        const SizedBox(height: 16),
        Center(child: CircleAvatar(radius: 36, child: Text(link.displayName.isEmpty ? '?' : link.displayName[0].toUpperCase(), style: const TextStyle(fontSize: 28)))),
        const SizedBox(height: 8),
        Center(child: Text(link.displayName, style: Theme.of(context).textTheme.titleLarge)),
        const SizedBox(height: 12),
        ListTile(leading: const Icon(Icons.badge_outlined), title: const Text('Teacher record'), subtitle: Text('${link.teacherName} (device ID ${link.teacherId})')),
        if (link.teacherNo.isNotEmpty) ListTile(leading: const Icon(Icons.numbers), title: const Text('Teacher ID'), subtitle: Text(link.teacherNo)),
        ListTile(leading: const Icon(Icons.menu_book_outlined), title: const Text('Subject'), subtitle: FacultyName(link.faculty)),
        if (link.position.isNotEmpty) ListTile(leading: const Icon(Icons.work_outline), title: const Text('Position'), subtitle: Text(link.position)),
        ListTile(leading: const Icon(Icons.email_outlined), title: const Text('Email'), subtitle: Text(link.email)),
        const Divider(),
        if (link.unlinkRequested)
          ListTile(
            leading: const Icon(Icons.hourglass_top),
            title: const Text('Unlink request sent'),
            subtitle: Text(link.unlinkReason.isEmpty ? 'Waiting for an admin to decide.' : 'Waiting for an admin. Your reason: ${link.unlinkReason}'),
            trailing: TextButton(onPressed: () => _run(context, Repo.cancelUnlink, 'Request cancelled.'), child: const Text('Cancel')),
          )
        else ...[
          if (link.adminNote.isNotEmpty) ListTile(leading: const Icon(Icons.sticky_note_2_outlined), title: const Text('Note from admin'), subtitle: Text(link.adminNote)),
          ListTile(leading: const Icon(Icons.link_off), title: const Text('Request unlink'), subtitle: const Text('Ask an admin to remove the link to this teacher record'), onTap: () => _requestUnlink(context)),
        ],
        const Divider(),
        ListTile(leading: const Icon(Icons.logout), title: const Text('Sign out'), onTap: () => signOut()),
      ]);
}

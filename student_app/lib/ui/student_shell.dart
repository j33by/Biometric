import 'package:flutter/material.dart';

import '../models.dart';
import '../repo.dart';
import 'common.dart';

class StudentShell extends StatefulWidget {
  final Link link;
  final VoidCallback onReload;
  const StudentShell({super.key, required this.link, required this.onReload});
  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _i = 0;
  static const _titles = ['Home', 'Attendance', 'Logs', 'Notices', 'Profile'];

  @override
  Widget build(BuildContext context) {
    final l = widget.link;
    final pages = <Widget>[
      HomeTab(link: l, goTo: (i) => setState(() => _i = i)),
      AttendanceTab(link: l),
      LogsTab(link: l),
      const NoticesTab(),
      ProfileTab(link: l, onReload: widget.onReload),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_i])),
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

/// First punch = In, last punch = Out (when there is more than one).
class DaySummary {
  final DateTime day;
  final List<DateTime> punches; // ascending
  DaySummary(this.day, this.punches);
  DateTime get first => punches.first;
  DateTime? get last => punches.length > 1 ? punches.last : null;
  String get inOut => 'In ${fTime.format(first)}${last == null ? ' · no Out yet' : ' · Out ${fTime.format(last!)}'}';
}

Map<DateTime, DaySummary> groupByDay(List<DateTime> logs) {
  final m = <DateTime, List<DateTime>>{};
  for (final t in logs) {
    m.putIfAbsent(dayOf(t), () => []).add(t);
  }
  return {for (final e in m.entries) e.key: DaySummary(e.key, e.value..sort())};
}

// ================================================================= Home
class HomeTab extends StatefulWidget {
  final Link link;
  final void Function(int) goTo;
  const HomeTab({super.key, required this.link, required this.goTo});
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  late Future<List<DateTime>> _today = _loadToday();
  late Future<List<Notice>> _notices = Repo.notices(limit: 3);

  Future<List<DateTime>> _loadToday() {
    final d = dayOf(DateTime.now());
    return Repo.logs(widget.link.studentId, d, d.add(const Duration(days: 1)));
  }

  Future<void> _reload() async {
    setState(() {
      _today = _loadToday();
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hello, ${l.displayName}', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Row(children: [Text('ID ${l.studentId} · '), SectionName(l.section)]),
          ]),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Today · ${fDay.format(DateTime.now())}", style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Busy<List<DateTime>>(
                future: _today,
                builder: (logs) {
                  if (logs.isEmpty) return const Text('No punches yet today.');
                  final s = DaySummary(dayOf(DateTime.now()), [...logs]..sort());
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.inOut, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, children: [for (final t in s.punches) Chip(label: Text(fTime.format(t)), visualDensity: VisualDensity.compact)]),
                  ]);
                },
              ),
            ]),
          ),
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
}

// ================================================================= Attendance
class AttendanceTab extends StatefulWidget {
  final Link link;
  const AttendanceTab({super.key, required this.link});
  @override
  State<AttendanceTab> createState() => _AttendanceTabState();
}

class _AttendanceTabState extends State<AttendanceTab> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  late Future<List<DateTime>> _f = _load();

  Future<List<DateTime>> _load() =>
      Repo.logs(widget.link.studentId, _month, DateTime(_month.year, _month.month + 1));

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

  void _showDay(DaySummary d) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(fDay.format(d.day), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(d.inOut),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 4, children: [for (final t in d.punches) Chip(label: Text(fTime.format(t)))]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _go(-1)),
          Text(fMonth.format(_month), style: Theme.of(context).textTheme.titleMedium),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: isCurrent ? null : () => _go(1)),
        ]),
        Busy<List<DateTime>>(
          future: _f,
          builder: (logs) {
            final days = groupByDay(logs);
            final first = DateTime(_month.year, _month.month, 1);
            final count = DateTime(_month.year, _month.month + 1, 0).day;
            final offset = first.weekday % 7; // Sunday first
            final cells = <Widget>[
              for (final w in 'SMTWTFS'.split('')) Center(child: Text(w, style: TextStyle(color: cs.outline, fontWeight: FontWeight.w600))),
              for (var i = 0; i < offset; i++) const SizedBox.shrink(),
              for (var d = 1; d <= count; d++) _cell(DateTime(_month.year, _month.month, d), days, cs),
            ];
            final sorted = days.values.toList()..sort((a, b) => b.day.compareTo(a.day));
            return Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  _stat('Days present', '${days.length}', cs),
                  _stat('Total punches', '${logs.length}', cs),
                  _stat('No Out', '${days.values.where((d) => d.last == null).length}', cs),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), mainAxisSpacing: 4, crossAxisSpacing: 4, children: cells),
              ),
              if (sorted.isEmpty) const Empty(Icons.event_busy, 'No attendance recorded this month.'),
              for (final d in sorted)
                ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.green),
                  title: Text(fDay.format(d.day)),
                  subtitle: Text(d.inOut),
                  trailing: Text('${d.punches.length} punch${d.punches.length == 1 ? '' : 'es'}', style: TextStyle(color: cs.outline)),
                  onTap: () => _showDay(d),
                ),
            ]);
          },
        ),
      ]),
    );
  }

  Widget _stat(String label, String value, ColorScheme cs) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(children: [
              Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              Text(label, style: TextStyle(color: cs.outline, fontSize: 12)),
            ]),
          ),
        ),
      );

  Widget _cell(DateTime d, Map<DateTime, DaySummary> days, ColorScheme cs) {
    final s = days[d];
    final today = dayOf(DateTime.now()) == d;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: s == null ? null : () => _showDay(s),
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: s == null ? null : cs.primaryContainer,
          borderRadius: BorderRadius.circular(8),
          border: today ? Border.all(color: cs.primary, width: 2) : null,
        ),
        child: Text('${d.day}', style: TextStyle(fontWeight: s == null ? FontWeight.normal : FontWeight.w700, color: s == null ? cs.outline : cs.onPrimaryContainer)),
      ),
    );
  }
}

// ================================================================= Logs
class LogsTab extends StatefulWidget {
  final Link link;
  const LogsTab({super.key, required this.link});
  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<LogsTab> {
  late Future<List<DateTime>> _f = _load();
  Future<List<DateTime>> _load() => Repo.logs(widget.link.studentId, DateTime.now().subtract(const Duration(days: 60)), DateTime.now().add(const Duration(days: 1)));

  Future<void> _reload() async {
    setState(() => _f = _load());
    try {
      await _f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: _reload,
        child: Busy<List<DateTime>>(
          future: _f,
          builder: (logs) {
            if (logs.isEmpty) return ListView(children: const [Empty(Icons.fingerprint, 'No punches in the last 60 days.')]);
            final days = groupByDay(logs).values.toList()..sort((a, b) => b.day.compareTo(a.day));
            return ListView(children: [
              for (final d in days) ...[
                Padding(padding: const EdgeInsets.fromLTRB(16, 14, 16, 4), child: Text(fDay.format(d.day), style: const TextStyle(fontWeight: FontWeight.w700))),
                for (var i = d.punches.length - 1; i >= 0; i--)
                  ListTile(dense: true, leading: const Icon(Icons.fingerprint, size: 20), title: Text(fTime.format(d.punches[i])),
                      trailing: Text(i == 0 ? 'First' : (i == d.punches.length - 1 ? 'Last' : ''))),
              ],
            ]);
          },
        ),
      );
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
    final reason = await askText(context,
        title: 'Request unlink',
        label: 'Why? (e.g. wrong record, new account)',
        lines: 2);
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
        ListTile(leading: const Icon(Icons.badge_outlined), title: const Text('Teachers record'), subtitle: Text('${link.studentName} (ID ${link.studentId})')),
        ListTile(leading: const Icon(Icons.groups_outlined), title: const Text('Section'), subtitle: SectionName(link.section)),
        if (link.lrn.isNotEmpty) ListTile(leading: const Icon(Icons.numbers), title: const Text('Teacher ID'), subtitle: Text(link.lrn)),
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
          ListTile(leading: const Icon(Icons.link_off), title: const Text('Request unlink'), subtitle: const Text('Ask an admin to remove the link to this student record'), onTap: () => _requestUnlink(context)),
        ],
        const Divider(),
        ListTile(leading: const Icon(Icons.logout), title: const Text('Sign out'), onTap: () => signOut()),
      ]);
}

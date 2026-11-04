import 'dart:async';

import 'package:flutter/material.dart';

import '../core/attendance.dart';
import '../core/dates.dart';
import '../core/models.dart';
import '../main.dart';
import 'nav.dart';
import 'theme.dart';
import 'widgets.dart';

class DashboardPage extends StatefulWidget {
  final ValueChanged<int> onNavigate;
  const DashboardPage({super.key, required this.onNavigate});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // keep "on duty now" honest as the Philippine clock moves
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  DateTime? _latestDate(Map<String, List<PunchLog>> by) {
    String? best;
    for (final k in by.keys) {
      if (by[k]!.isEmpty) continue;
      if (best == null || k.compareTo(best) > 0) best = k;
    }
    return best == null ? null : parseDate(best);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final book = app.book;
    final now = app.now; // Philippine time
    final today = dateOnly(now);
    final latest = _latestDate(app.logsByDate);
    final day = book.hasData(today) ? today : (latest ?? today);
    final isToday = day == today;
    final sum = book.summary(day);
    final trend = book.trend(day, 14);
    final hours = book.hourHistogram(day, 30);
    final byFac = book.byFaculty(day);
    final late = book.topLate(day, 30);
    final abs = book.topAbsent(day, 30);
    final noData = app.logs.isEmpty;
    final duty = book.dutyAt(now);

    final recent = <PunchLog>[];
    final keys = app.logsByDate.keys.toList()..sort((a, b) => b.compareTo(a));
    for (final k in keys) {
      final l = [...app.logsByDate[k]!]..sort((a, b) => b.time.compareTo(a.time));
      recent.addAll(l);
      if (recent.length >= 8) break;
    }

    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      PageHeader(
        title: isToday ? 'Today' : 'Latest day with data',
        subtitle: fmtDateLong(day) + (isToday ? '' : '  ·  nothing imported for today yet'),
        actions: [
          OutlinedButton.icon(onPressed: () => widget.onNavigate(kNavSync), icon: const Icon(Icons.usb_rounded, size: 16), label: const Text('Import from device')),
        ],
      ),
      if (app.clockWarning != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: C.warnSoft, border: Border.all(color: C.warn), borderRadius: BorderRadius.circular(4)),
            child: Row(children: [
              const Icon(Icons.schedule, color: C.warn, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(app.clockWarning!, style: const TextStyle(color: C.ink, height: 1.35))),
              TextButton(onPressed: () => widget.onNavigate(kNavSync), child: const Text('Fix')),
            ]),
          ),
        ),
      if (noData)
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('No attendance data yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Download the logs from the biometric device to a USB stick and plug it in. The app imports Attendance_Logs.txt by itself,\nor use Device sync to pick the file manually.', style: TextStyle(color: C.muted, height: 1.4)),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => widget.onNavigate(kNavSync), child: const Text('Open device sync')),
          ]),
        )
      else ...[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Kpi(label: 'Teachers', value: '${book.teachers.length}', note: '${app.faculty.values.where((s) => book.teachers.any((x) => x.faculty == s.no)).length} subjects')),
          const SizedBox(width: 12),
          Expanded(child: Kpi(label: 'Present', value: '${sum.present}', color: C.ok, note: sum.rate == null ? null : '${(sum.rate! * 100).round()}% of ${sum.expected} on duty')),
          const SizedBox(width: 12),
          Expanded(child: Kpi(label: 'Late', value: '${sum.late}', color: C.warn, note: 'logged in after the shift start')),
          const SizedBox(width: 12),
          Expanded(child: Kpi(label: 'Absent', value: '${sum.absent}', color: C.bad, note: 'on duty, no punch recorded')),
          const SizedBox(width: 12),
          Expanded(child: Kpi(label: 'On leave', value: '${sum.onLeave}', color: C.accent, note: 'excused, not counted absent')),
        ]),
        const SizedBox(height: 14),
        if (isToday) ...[
          Panel(
            title: 'On duty now · ${fmtTime12(now)} PHT',
            trailing: Text(app.lastImport == null ? 'punches imported: not this session' : 'punches imported ${fmtAgo(app.lastImport!)}', style: const TextStyle(fontSize: 11.5, color: C.muted)),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: _DutyList(duty: duty),
          ),
          const SizedBox(height: 14),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: Panel(
              title: 'Attendance rate · last 14 days',
              child: SizedBox(
                height: 190,
                child: TrendChart(
                  values: trend.map((e) => e.rate).toList(),
                  labels: trend.map((e) => fmtDayMonth(e.date)).toList(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 2,
            child: Panel(
              title: 'Split · ${fmtDayMonth(day)}',
              child: SizedBox(
                height: 190,
                child: Row(children: [
                  SizedBox(
                    width: 150,
                    child: Ring(
                      present: sum.present,
                      late: sum.late,
                      absent: sum.absent,
                      centre: sum.rate == null ? '–' : '${(sum.rate! * 100).round()}%',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _legend(C.ok, 'On time', sum.present - sum.late),
                      _legend(C.warn, 'Late', sum.late),
                      _legend(C.bad, 'Absent', sum.absent),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            flex: 3,
            child: Panel(
              title: 'Punches by hour · last 30 days',
              child: SizedBox(height: 150, child: HourBars(counts: hours)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            flex: 2,
            child: Panel(
              title: 'By subject · ${fmtDayMonth(day)}',
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: byFac.isEmpty
                  ? const EmptyNote('No subjects with teachers')
                  : Column(children: [
                      for (final s in byFac)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(children: [
                            Expanded(child: Text(app.facultyName(s.faculty.no), overflow: TextOverflow.ellipsis)),
                            Text(s.expected == 0 ? 'no duty' : '${s.present}/${s.expected}', style: const TextStyle(color: C.muted, fontSize: 12)),
                            const SizedBox(width: 10),
                            RateBar(s.rate, width: 130),
                          ]),
                        ),
                    ]),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Panel(
              title: 'Most often late · 30 days',
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: late.isEmpty
                  ? const EmptyNote('Nobody was late')
                  : Column(children: [for (final r in late) _rankRow(r, '${r.days} days · ${fmtDuration(r.minutes)} total', C.warn)]),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Panel(
              title: 'Most absences · 30 days',
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: abs.isEmpty
                  ? const EmptyNote('No absences')
                  : Column(children: [for (final r in abs) _rankRow(r, '${r.days} day${r.days == 1 ? '' : 's'}', C.bad)]),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Panel(
              title: 'Latest punches',
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
              child: recent.isEmpty
                  ? const EmptyNote('Nothing yet')
                  : Column(children: [
                      for (final l in recent.take(8))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(children: [
                            SizedBox(width: 92, child: Text('${fmtDayMonth(l.time)} ${fmtTime12(l.time)}', style: const TextStyle(fontSize: 12, color: C.muted))),
                            Expanded(child: Text(app.teacherById(l.teacherId)?.name ?? l.name, overflow: TextOverflow.ellipsis)),
                          ]),
                        ),
                    ]),
            ),
          ),
        ]),
      ],
    ]);
  }

  Widget _legend(Color c, String label, int n) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Container(width: 10, height: 10, color: c),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text('$n', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );

  Widget _rankRow(LateRank r, String detail, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(child: Text(r.teacher.name, overflow: TextOverflow.ellipsis)),
          Text(detail, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Teachers with duty today: on duty first, then who starts next, then who has finished.
class _DutyList extends StatelessWidget {
  final List<DutyNow> duty;
  const _DutyList({required this.duty});

  @override
  Widget build(BuildContext context) {
    if (duty.isEmpty) return const EmptyNote('Nobody has duty today.');
    return Column(children: [
      for (final d in duty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 20, child: Icon(_icon(d), size: 16, color: _color(d))),
            Expanded(flex: 3, child: Text(d.teacher.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
            Expanded(flex: 2, child: Text(d.schedule, style: const TextStyle(color: C.muted, fontSize: 12.5))),
            SizedBox(width: 190, child: Align(alignment: Alignment.centerLeft, child: _state(d))),
          ]),
        ),
    ]);
  }

  IconData _icon(DutyNow d) =>
      d.phase == DutyPhase.onDuty ? Icons.circle : (d.phase == DutyPhase.upcoming ? Icons.schedule : Icons.check_circle_outline);

  Color _color(DutyNow d) {
    if (d.notInYet) return C.bad;
    return d.phase == DutyPhase.onDuty ? C.ok : (d.phase == DutyPhase.upcoming ? C.accent : C.faint);
  }

  Widget _state(DutyNow d) {
    if (d.notInYet) return const Tag('Not logged in', fg: C.bad, bg: C.badSoft);
    if (d.phase == DutyPhase.upcoming) {
      final m = d.minutesToStart;
      return Tag('Starts in ${m >= 60 ? fmtDuration(m) : '$m min'}', fg: C.accent, bg: C.accentSoft);
    }
    if (d.inTime == null) return const Tag('Waiting for log-in', fg: C.muted, bg: C.surfaceAlt);
    final base = 'In ${fmtTime12(d.inTime!)}';
    if (d.phase == DutyPhase.finished) {
      final out = d.outTime;
      final txt = out == null ? '$base · no log-out' : '$base · Out ${fmtTime12(out)}';
      return Tag(txt, fg: out == null ? C.warn : C.muted, bg: out == null ? C.warnSoft : C.surfaceAlt);
    }
    return d.lateMin > 0
        ? Tag('$base · ${d.lateMin} min late', fg: C.warn, bg: C.warnSoft)
        : Tag(base, fg: C.ok, bg: C.okSoft);
  }
}

import 'package:flutter/material.dart';

import '../core/attendance.dart';
import '../core/dates.dart';
import '../core/models.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

class DashboardPage extends StatelessWidget {
  final ValueChanged<int> onNavigate;
  const DashboardPage({super.key, required this.onNavigate});

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
    final today = dateOnly(DateTime.now());
    final latest = _latestDate(app.logsByDate);
    final day = book.hasData(today) ? today : (latest ?? today);
    final isToday = day == today;
    final sum = book.summary(day);
    final trend = book.trend(day, 14);
    final hours = book.hourHistogram(day, 30);
    final bySec = book.bySection(day);
    final late = book.topLate(day, 30);
    final abs = book.topAbsent(day, 30);
    final noData = app.logs.isEmpty;

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
        subtitle: fmtDateLong(day) +
            (isToday ? '' : '  ·  nothing imported for today yet'),
        actions: [
          OutlinedButton.icon(onPressed: () => onNavigate(4), icon: const Icon(Icons.usb_rounded, size: 16), label: const Text('Import from device')),
        ],
      ),
      if (noData)
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('No attendance data yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('Download the logs from the biometric device to a USB stick and plug it in. The app imports Attendance_Logs.txt by itself,\nor use Device sync to pick the file manually.', style: TextStyle(color: C.muted, height: 1.4)),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => onNavigate(4), child: const Text('Open device sync')),
          ]),
        )
      else ...[
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Kpi(label: 'Enrolled', value: '${book.students.length}', note: '${app.sections.values.where((s) => book.students.any((x) => x.section == s.no)).length} sections')),
          const SizedBox(width: 12),
          Expanded(child: Kpi(label: 'Present', value: '${sum.present}', color: C.ok, note: sum.rate == null ? null : '${(sum.rate! * 100).round()}% of ${sum.expected}')),
          const SizedBox(width: 12),
          Expanded(child: Kpi(label: 'Late', value: '${sum.late}', color: C.warn, note: 'arrived after the bell')),
          const SizedBox(width: 12),
          Expanded(child: Kpi(label: 'Absent', value: '${sum.absent}', color: C.bad, note: 'no punch recorded')),
          const SizedBox(width: 12),
          Expanded(child: Kpi(label: 'Punches', value: '${sum.punches}', note: 'raw device records')),
        ]),
        const SizedBox(height: 14),
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
              title: 'By section · ${fmtDayMonth(day)}',
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
              child: bySec.isEmpty
                  ? const EmptyNote('No sections with teachers')
                  : Column(children: [
                      for (final s in bySec)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: Row(children: [
                            Expanded(child: Text(app.sectionName(s.section.no), overflow: TextOverflow.ellipsis)),
                            Text('${s.present}/${s.expected}', style: const TextStyle(color: C.muted, fontSize: 12)),
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
                            SizedBox(width: 78, child: Text('${fmtDayMonth(l.time)} ${fmtTime(l.time)}', style: const TextStyle(fontSize: 12, color: C.muted))),
                            Expanded(child: Text(app.studentById(l.studentId)?.name ?? l.name, overflow: TextOverflow.ellipsis)),
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
          Expanded(child: Text(r.student.name, overflow: TextOverflow.ellipsis)),
          Text(detail, style: TextStyle(fontSize: 12, color: c, fontWeight: FontWeight.w600)),
        ]),
      );
}

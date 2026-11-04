// Attendance maths: raw punches -> per-teacher day records -> statistics.
//
// A teacher's day is decided by their faculty slot: the slot's weekly pattern
// names a shift for each weekday, and the shift holds the log-in / log-out
// times (Philippine time).  The late / early rules are in schedule_calc.dart
// (shared with the phone app) and follow the device's own report.

import 'dates.dart';
import 'models.dart';
import 'schedule_calc.dart';

enum DayStatus { present, late, absent, dayOff, leave, noData }

class DayRecord {
  final Teacher teacher;
  final DateTime date;
  final DayStatus status;
  final DateTime? in1, out1, in2, out2;
  final int lateMin;
  final int earlyMin;
  final int otMin;
  final int punches;
  final bool missedOut;
  final int shiftNo;
  final String schedule; // "7:50 – 9:50 AM" or '' when there is no duty
  final String? leaveType;

  const DayRecord({
    required this.teacher,
    required this.date,
    required this.status,
    this.in1,
    this.out1,
    this.in2,
    this.out2,
    this.lateMin = 0,
    this.earlyMin = 0,
    this.otMin = 0,
    this.punches = 0,
    this.missedOut = false,
    this.shiftNo = 0,
    this.schedule = '',
    this.leaveType,
  });

  bool get attended => status == DayStatus.present || status == DayStatus.late;
  DateTime? get lastOut => out2 ?? out1;

  /// Minutes between log-in and last log-out (0 if either is missing).
  int get workedMin {
    final a = in1, b = lastOut;
    if (a == null || b == null) return 0;
    final d = b.difference(a).inMinutes;
    return d > 0 ? d : 0;
  }
}

class DaySummary {
  final DateTime date;
  final bool hasData;
  final int expected;
  final int present;
  final int late;
  final int absent;
  final int onLeave;
  final int punches;
  const DaySummary(this.date, this.hasData, this.expected, this.present, this.late, this.absent, this.onLeave, this.punches);

  double? get rate => (!hasData || expected == 0) ? null : present / expected;
}

class LateRank {
  final Teacher teacher;
  final int days;
  final int minutes;
  const LateRank(this.teacher, this.days, this.minutes);
}

class FacultyDay {
  final Faculty faculty;
  final int expected, present, late, absent;
  const FacultyDay(this.faculty, this.expected, this.present, this.late, this.absent);
  double? get rate => expected == 0 ? null : present / expected;
}

enum DutyPhase { upcoming, onDuty, finished }

/// One teacher's duty today, seen from a given Philippine time.
class DutyNow {
  final Teacher teacher;
  final String schedule; // "7:50 – 9:50 AM"
  final int startMin, endMin;
  final DutyPhase phase;
  final DateTime? inTime;
  final DateTime? outTime;
  final int lateMin;
  final bool notInYet; // duty has started (past the allowance) and no log-in
  final int minutesToStart; // > 0 while upcoming
  const DutyNow({
    required this.teacher,
    required this.schedule,
    required this.startMin,
    required this.endMin,
    required this.phase,
    this.inTime,
    this.outTime,
    this.lateMin = 0,
    this.notInYet = false,
    this.minutesToStart = 0,
  });
}

class MonthStats {
  final int scheduledDays; // days with duty, excluding leave
  final int present; // includes late
  final int late;
  final int absent;
  final int leave;
  final int lateMin;
  final int earlyMin;
  final int missedOut;
  final int workedMin;
  final int scheduledMin; // duty minutes of the days counted above
  const MonthStats(this.scheduledDays, this.present, this.late, this.absent, this.leave, this.lateMin,
      this.earlyMin, this.missedOut, this.workedMin, this.scheduledMin);

  double? get rate => scheduledDays == 0 ? null : present / scheduledDays;
}

class AttendanceBook {
  final List<Teacher> teachers; // active only
  final Map<int, Faculty> faculty;
  final Map<int, Shift> shifts;
  final Rules rules;
  final Map<String, List<PunchLog>> logsByDate;
  final Map<int, List<LeaveRecord>> _leaves = {};
  final Map<String, List<DayRecord>> _cache = {};

  AttendanceBook({
    required List<Teacher> teachers,
    required this.faculty,
    required this.shifts,
    required this.rules,
    required this.logsByDate,
    List<LeaveRecord> leaves = const [],
  }) : teachers = teachers.where((s) => !s.deleted).toList()..sort((a, b) => a.id.compareTo(b.id)) {
    for (final l in leaves) {
      if (!l.deleted) _leaves.putIfAbsent(l.teacherId, () => []).add(l);
    }
  }

  bool hasData(DateTime day) => (logsByDate[fmtDate(day)]?.isNotEmpty ?? false);

  int punchCount(DateTime day) => logsByDate[fmtDate(day)]?.length ?? 0;

  LeaveRecord? leaveFor(int teacherId, DateTime day) {
    final l = _leaves[teacherId];
    if (l == null) return null;
    for (final x in l) {
      if (x.covers(day)) return x;
    }
    return null;
  }

  /// The shift a teacher is on for [date], or null when they have no duty.
  Shift? shiftFor(Teacher t, DateTime date) {
    final f = faculty[t.faculty];
    final no = f == null ? 1 : f.week[deviceWeekday(date)];
    return no == 0 ? null : shifts[no];
  }

  List<DayRecord> day(DateTime d) {
    final key = fmtDate(d);
    return _cache.putIfAbsent(key, () {
      final logs = logsByDate[key] ?? const <PunchLog>[];
      final byTeacher = <int, List<PunchLog>>{};
      for (final l in logs) {
        byTeacher.putIfAbsent(l.teacherId, () => []).add(l);
      }
      final any = logs.isNotEmpty;
      return teachers
          .map((s) => _compute(s, dateOnly(d), byTeacher[s.id] ?? const <PunchLog>[], any))
          .toList(growable: false);
    });
  }

  DayRecord? recordFor(Teacher s, DateTime d) {
    for (final r in day(d)) {
      if (r.teacher.id == s.id) return r;
    }
    return null;
  }

  DaySummary summary(DateTime d) {
    final recs = day(d);
    var expected = 0, present = 0, late = 0, absent = 0, leave = 0;
    for (final r in recs) {
      if (r.status == DayStatus.leave) leave++;
      if (r.status == DayStatus.dayOff || r.status == DayStatus.noData || r.status == DayStatus.leave) continue;
      expected++;
      if (r.attended) present++;
      if (r.status == DayStatus.late) late++;
      if (r.status == DayStatus.absent) absent++;
    }
    return DaySummary(dateOnly(d), hasData(d), expected, present, late, absent, leave, punchCount(d));
  }

  List<DaySummary> trend(DateTime end, int days) {
    return List.generate(days, (i) => summary(dateOnly(end).subtract(Duration(days: days - 1 - i))));
  }

  /// Punch counts by hour of day over [days] days ending at [end].
  List<int> hourHistogram(DateTime end, int days) {
    final h = List<int>.filled(24, 0);
    for (var i = 0; i < days; i++) {
      final logs = logsByDate[fmtDate(dateOnly(end).subtract(Duration(days: i)))];
      if (logs == null) continue;
      for (final l in logs) {
        h[l.time.hour]++;
      }
    }
    return h;
  }

  List<LateRank> topLate(DateTime end, int days, {int limit = 5}) {
    final days_ = <int, int>{};
    final mins = <int, int>{};
    final byId = {for (final s in teachers) s.id: s};
    for (var i = 0; i < days; i++) {
      for (final r in day(dateOnly(end).subtract(Duration(days: i)))) {
        if (r.status == DayStatus.late) {
          days_[r.teacher.id] = (days_[r.teacher.id] ?? 0) + 1;
          mins[r.teacher.id] = (mins[r.teacher.id] ?? 0) + r.lateMin;
        }
      }
    }
    final ranks = days_.entries
        .where((e) => byId.containsKey(e.key))
        .map((e) => LateRank(byId[e.key]!, e.value, mins[e.key] ?? 0))
        .toList()
      ..sort((a, b) => b.days != a.days ? b.days.compareTo(a.days) : b.minutes.compareTo(a.minutes));
    return ranks.take(limit).toList();
  }

  /// Teachers with the most absences over the last [days] days that had data.
  List<LateRank> topAbsent(DateTime end, int days, {int limit = 5}) {
    final counts = <int, int>{};
    final byId = {for (final s in teachers) s.id: s};
    for (var i = 0; i < days; i++) {
      for (final r in day(dateOnly(end).subtract(Duration(days: i)))) {
        if (r.status == DayStatus.absent) counts[r.teacher.id] = (counts[r.teacher.id] ?? 0) + 1;
      }
    }
    final ranks = counts.entries
        .where((e) => byId.containsKey(e.key))
        .map((e) => LateRank(byId[e.key]!, e.value, 0))
        .toList()
      ..sort((a, b) => b.days.compareTo(a.days));
    return ranks.take(limit).toList();
  }

  List<FacultyDay> byFaculty(DateTime d) {
    final out = <FacultyDay>[];
    final recs = day(d);
    final nos = faculty.keys.toList()..sort();
    for (final no in nos) {
      var expected = 0, present = 0, late = 0, absent = 0;
      for (final r in recs) {
        if (r.teacher.faculty != no) continue;
        if (r.status == DayStatus.dayOff || r.status == DayStatus.noData || r.status == DayStatus.leave) continue;
        expected++;
        if (r.attended) present++;
        if (r.status == DayStatus.late) late++;
        if (r.status == DayStatus.absent) absent++;
      }
      final hasTeachers = teachers.any((s) => s.faculty == no);
      if (hasTeachers) out.add(FacultyDay(faculty[no]!, expected, present, late, absent));
    }
    return out;
  }

  /// Everyone who has duty today, as seen at the Philippine wall-clock time [now].
  /// Sorted: on duty first, then the next to start, then finished.
  List<DutyNow> dutyAt(DateTime now) {
    final date = dateOnly(now);
    final nowMin = now.hour * 60 + now.minute;
    final recs = day(date);
    final out = <DutyNow>[];
    for (final r in recs) {
      if (r.shiftNo == 0 || r.status == DayStatus.leave) continue;
      final shift = shiftFor(r.teacher, date);
      if (shift == null || shift.isEmpty) continue;
      final start = shift.times.startMin, end = shift.times.endMin;
      if (start == null || end == null) continue;
      final phase = nowMin < start ? DutyPhase.upcoming : (nowMin <= end ? DutyPhase.onDuty : DutyPhase.finished);
      // Only call someone "not in" when punches for today were actually imported;
      // an empty day just means the device has not been downloaded yet.
      final notIn = hasData(date) && phase != DutyPhase.upcoming && r.in1 == null && nowMin > start + rules.lateAllow;
      out.add(DutyNow(
        teacher: r.teacher,
        schedule: shift.label,
        startMin: start,
        endMin: end,
        phase: phase,
        inTime: r.in1,
        outTime: r.lastOut,
        lateMin: r.lateMin,
        notInYet: notIn,
        minutesToStart: phase == DutyPhase.upcoming ? start - nowMin : 0,
      ));
    }
    int rank(DutyPhase p) => p == DutyPhase.onDuty ? 0 : (p == DutyPhase.upcoming ? 1 : 2);
    out.sort((a, b) {
      final c = rank(a.phase).compareTo(rank(b.phase));
      return c != 0 ? c : a.startMin.compareTo(b.startMin);
    });
    return out;
  }

  /// Totals for one teacher over a calendar month ([month] is any date in it).
  /// Days without any imported data are skipped (they are "no data", not absences).
  MonthStats month(Teacher t, DateTime month) {
    final last = DateTime(month.year, month.month + 1, 0).day;
    var sched = 0, present = 0, late = 0, absent = 0, leave = 0;
    var lateMin = 0, earlyMin = 0, missed = 0, worked = 0, schedMin = 0;
    for (var d = 1; d <= last; d++) {
      final date = DateTime(month.year, month.month, d);
      final r = recordFor(t, date);
      if (r == null) continue;
      if (r.status == DayStatus.leave) {
        leave++;
        continue;
      }
      if (r.status == DayStatus.noData || r.status == DayStatus.dayOff) continue;
      sched++;
      schedMin += shiftFor(t, date)?.dutyMinutes ?? 0;
      if (r.attended) {
        present++;
        worked += r.workedMin;
        earlyMin += r.earlyMin;
        if (r.missedOut) missed++;
      }
      if (r.status == DayStatus.late) {
        late++;
        lateMin += r.lateMin;
      }
      if (r.status == DayStatus.absent) absent++;
    }
    return MonthStats(sched, present, late, absent, leave, lateMin, earlyMin, missed, worked, schedMin);
  }

  // ------------------------------------------------------------ core

  DayRecord _compute(Teacher s, DateTime date, List<PunchLog> raw, bool dayHasAnyData) {
    final f = faculty[s.faculty];
    final shiftNo = f == null ? 1 : f.week[deviceWeekday(date)];
    final shift = shiftNo == 0 ? null : shifts[shiftNo];
    final schedule = (shift == null || shift.isEmpty) ? '' : shift.label;

    final t = calcDay(
      shift: shift?.times,
      rules: rules.values,
      rawPunches: raw.map((e) => e.time).toList(),
    );

    if (shiftNo == 0) {
      if (t == null) {
        return DayRecord(teacher: s, date: date, status: DayStatus.dayOff, shiftNo: 0);
      }
      return DayRecord(
          teacher: s, date: date, status: DayStatus.present, in1: t.in1, out1: t.out1, punches: t.punches, shiftNo: 0);
    }

    if (t == null) {
      final leave = leaveFor(s.id, date);
      if (leave != null) {
        return DayRecord(
            teacher: s, date: date, status: DayStatus.leave, shiftNo: shiftNo, schedule: schedule, leaveType: leave.type);
      }
      return DayRecord(
          teacher: s,
          date: date,
          status: dayHasAnyData ? DayStatus.absent : DayStatus.noData,
          shiftNo: shiftNo,
          schedule: schedule);
    }

    return DayRecord(
      teacher: s,
      date: date,
      status: t.lateMin > 0 ? DayStatus.late : DayStatus.present,
      in1: t.in1,
      out1: t.out1,
      in2: t.in2,
      out2: t.out2,
      lateMin: t.lateMin,
      earlyMin: t.earlyMin,
      otMin: t.otMin,
      punches: t.punches,
      missedOut: t.missedOut,
      shiftNo: shiftNo,
      schedule: schedule,
    );
  }
}

String statusLabel(DayStatus s) {
  switch (s) {
    case DayStatus.present:
      return 'Present';
    case DayStatus.late:
      return 'Late';
    case DayStatus.absent:
      return 'Absent';
    case DayStatus.dayOff:
      return 'No class';
    case DayStatus.leave:
      return 'On leave';
    case DayStatus.noData:
      return 'No data';
  }
}

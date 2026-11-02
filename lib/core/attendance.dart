// Attendance maths: raw punches -> per-student day records -> statistics.
//
// Rules follow the device's own report (checked against its exported
// "All_Report.xls"): In = first punch, Out = last distinct punch, late =
// In minus shift start (after allowance), early = shift end minus Out.

import 'dates.dart';
import 'models.dart';

enum DayStatus { present, late, absent, holiday, noData }

class DayRecord {
  final Student student;
  final DateTime date;
  final DayStatus status;
  final DateTime? in1, out1, in2, out2;
  final int lateMin;
  final int earlyMin;
  final int otMin;
  final int punches;
  final bool missedOut;
  final int shiftNo;

  const DayRecord({
    required this.student,
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
  });

  bool get attended => status == DayStatus.present || status == DayStatus.late;
}

class DaySummary {
  final DateTime date;
  final bool hasData;
  final int expected;
  final int present;
  final int late;
  final int absent;
  final int punches;
  const DaySummary(this.date, this.hasData, this.expected, this.present, this.late, this.absent, this.punches);

  double? get rate => (!hasData || expected == 0) ? null : present / expected;
}

class LateRank {
  final Student student;
  final int days;
  final int minutes;
  const LateRank(this.student, this.days, this.minutes);
}

class SectionDay {
  final Section section;
  final int expected, present, late, absent;
  const SectionDay(this.section, this.expected, this.present, this.late, this.absent);
  double? get rate => expected == 0 ? null : present / expected;
}

class AttendanceBook {
  final List<Student> students; // active only
  final Map<int, Section> sections;
  final Map<int, Shift> shifts;
  final Rules rules;
  final Map<String, List<PunchLog>> logsByDate;
  final Map<String, List<DayRecord>> _cache = {};

  AttendanceBook({
    required List<Student> students,
    required this.sections,
    required this.shifts,
    required this.rules,
    required this.logsByDate,
  }) : students = students.where((s) => !s.deleted).toList()..sort((a, b) => a.id.compareTo(b.id));

  bool hasData(DateTime day) => (logsByDate[fmtDate(day)]?.isNotEmpty ?? false);

  int punchCount(DateTime day) => logsByDate[fmtDate(day)]?.length ?? 0;

  List<DayRecord> day(DateTime d) {
    final key = fmtDate(d);
    return _cache.putIfAbsent(key, () {
      final logs = logsByDate[key] ?? const <PunchLog>[];
      final byStudent = <int, List<PunchLog>>{};
      for (final l in logs) {
        byStudent.putIfAbsent(l.studentId, () => []).add(l);
      }
      final any = logs.isNotEmpty;
      return students
          .map((s) => _compute(s, dateOnly(d), byStudent[s.id] ?? const <PunchLog>[], any))
          .toList(growable: false);
    });
  }

  DayRecord? recordFor(Student s, DateTime d) {
    for (final r in day(d)) {
      if (r.student.id == s.id) return r;
    }
    return null;
  }

  DaySummary summary(DateTime d) {
    final recs = day(d);
    var expected = 0, present = 0, late = 0, absent = 0;
    for (final r in recs) {
      if (r.status == DayStatus.holiday || r.status == DayStatus.noData) continue;
      expected++;
      if (r.attended) present++;
      if (r.status == DayStatus.late) late++;
      if (r.status == DayStatus.absent) absent++;
    }
    return DaySummary(dateOnly(d), hasData(d), expected, present, late, absent, punchCount(d));
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
    final byId = {for (final s in students) s.id: s};
    for (var i = 0; i < days; i++) {
      for (final r in day(dateOnly(end).subtract(Duration(days: i)))) {
        if (r.status == DayStatus.late) {
          days_[r.student.id] = (days_[r.student.id] ?? 0) + 1;
          mins[r.student.id] = (mins[r.student.id] ?? 0) + r.lateMin;
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

  /// Students with the most absences over the last [days] days that had data.
  List<LateRank> topAbsent(DateTime end, int days, {int limit = 5}) {
    final counts = <int, int>{};
    final byId = {for (final s in students) s.id: s};
    for (var i = 0; i < days; i++) {
      for (final r in day(dateOnly(end).subtract(Duration(days: i)))) {
        if (r.status == DayStatus.absent) counts[r.student.id] = (counts[r.student.id] ?? 0) + 1;
      }
    }
    final ranks = counts.entries
        .where((e) => byId.containsKey(e.key))
        .map((e) => LateRank(byId[e.key]!, e.value, 0))
        .toList()
      ..sort((a, b) => b.days.compareTo(a.days));
    return ranks.take(limit).toList();
  }

  List<SectionDay> bySection(DateTime d) {
    final out = <SectionDay>[];
    final recs = day(d);
    final nos = sections.keys.toList()..sort();
    for (final no in nos) {
      var expected = 0, present = 0, late = 0, absent = 0;
      for (final r in recs) {
        if (r.student.section != no) continue;
        if (r.status == DayStatus.holiday || r.status == DayStatus.noData) continue;
        expected++;
        if (r.attended) present++;
        if (r.status == DayStatus.late) late++;
        if (r.status == DayStatus.absent) absent++;
      }
      final hasStudents = students.any((s) => s.section == no);
      if (hasStudents) out.add(SectionDay(sections[no]!, expected, present, late, absent));
    }
    return out;
  }

  // ------------------------------------------------------------ core

  DayRecord _compute(Student s, DateTime date, List<PunchLog> raw, bool dayHasAnyData) {
    final sec = sections[s.section];
    final shiftNo = sec == null ? 1 : sec.week[deviceWeekday(date)];
    final shift = shiftNo == 0 ? null : shifts[shiftNo];

    // drop repeated verifications
    final sorted = [...raw]..sort((a, b) => a.time.compareTo(b.time));
    final punches = <DateTime>[];
    for (final p in sorted) {
      if (punches.isNotEmpty && p.time.difference(punches.last).inMinutes < rules.repeatMin) continue;
      punches.add(p.time);
    }

    if (shiftNo == 0) {
      if (punches.isEmpty) {
        return DayRecord(student: s, date: date, status: DayStatus.holiday, shiftNo: 0);
      }
      return DayRecord(
          student: s,
          date: date,
          status: DayStatus.present,
          in1: punches.first,
          out1: punches.length > 1 ? punches.last : null,
          punches: punches.length,
          shiftNo: 0);
    }

    if (punches.isEmpty) {
      return DayRecord(
          student: s,
          date: date,
          status: dayHasAnyData ? DayStatus.absent : DayStatus.noData,
          shiftNo: shiftNo);
    }

    int mins(DateTime t) => t.hour * 60 + t.minute;

    // overtime window
    var regular = punches;
    var otMin = 0;
    if (shift != null && shift.hasOvertime) {
      final otIn = parseHm(shift.otIn)!;
      final otOut = parseHm(shift.otOut)!;
      final ot = punches.where((p) => mins(p) >= otIn - 30).toList();
      regular = punches.where((p) => mins(p) < otIn - 30).toList();
      if (ot.length > 1) {
        final start = mins(ot.first) > otIn ? mins(ot.first) : otIn;
        final end = mins(ot.last) < otOut ? mins(ot.last) : otOut;
        if (end > start) otMin = end - start;
      }
    }

    // split into period 1 / period 2
    List<DateTime> p1 = regular, p2 = const [];
    if (shift != null && shift.hasSecondPeriod) {
      final o1 = parseHm(shift.out1);
      final i2 = parseHm(shift.in2);
      if (o1 != null && i2 != null) {
        final mid = (o1 + i2) ~/ 2;
        p1 = regular.where((p) => mins(p) < mid).toList();
        p2 = regular.where((p) => mins(p) >= mid).toList();
      }
    }

    DateTime? in1, out1, in2, out2;
    if (p1.isNotEmpty) {
      in1 = p1.first;
      if (p1.length > 1) out1 = p1.last;
    }
    if (p2.isNotEmpty) {
      in2 = p2.first;
      if (p2.length > 1) out2 = p2.last;
    }

    var late = 0, early = 0;
    if (shift != null && !shift.isEmpty) {
      final sIn1 = parseHm(shift.in1);
      final sOut1 = parseHm(shift.out1);
      if (in1 != null && sIn1 != null) {
        final v = mins(in1) - sIn1 - rules.lateAllow;
        if (v > 0) late += mins(in1) - sIn1;
      }
      if (out1 != null && sOut1 != null && !shift.hasSecondPeriod) {
        final v = sOut1 - rules.earlyAllow - mins(out1);
        if (v > 0) early += sOut1 - mins(out1);
      }
      if (shift.hasSecondPeriod) {
        final sIn2 = parseHm(shift.in2);
        final sOut2 = parseHm(shift.out2);
        if (in2 != null && sIn2 != null) {
          final v = mins(in2) - sIn2 - rules.lateAllow;
          if (v > 0) late += mins(in2) - sIn2;
        }
        final lastOut = out2 ?? out1;
        if (lastOut != null && sOut2 != null) {
          final v = sOut2 - rules.earlyAllow - mins(lastOut);
          if (v > 0) early += sOut2 - mins(lastOut);
        }
      }
    }

    final hasOut = shift != null && shift.hasSecondPeriod ? (out2 != null || out1 != null) : out1 != null;
    return DayRecord(
      student: s,
      date: date,
      status: late > 0 ? DayStatus.late : DayStatus.present,
      in1: in1,
      out1: out1,
      in2: in2,
      out2: out2,
      lateMin: late,
      earlyMin: early,
      otMin: otMin,
      punches: punches.length,
      missedOut: !hasOut,
      shiftNo: shiftNo,
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
    case DayStatus.holiday:
      return 'No class';
    case DayStatus.noData:
      return 'No data';
  }
}

// CSV reports (open in Excel).  Pure functions over an AttendanceBook.

import 'attendance.dart';
import 'dates.dart';
import 'models.dart';

String _q(String s) => '"${s.replaceAll('"', '""')}"';

String _t(DateTime? d) => d == null ? '' : fmtTime(d);

/// One day, every teacher.
String dayCsv(AttendanceBook book, DateTime day, String Function(int) facultyName) {
  final sb = StringBuffer('\uFEFF');
  sb.writeln('Device ID,Teacher,Subject,Status,Scheduled,In,Out,Late (min),Early out (min),Punches');
  for (final r in book.day(day)) {
    sb.writeln([
      r.teacher.id,
      _q(r.teacher.name),
      _q(facultyName(r.teacher.faculty)),
      r.status == DayStatus.leave ? _q('On leave: ${r.leaveType ?? ''}') : statusLabel(r.status),
      _q(r.schedule),
      _t(r.in1),
      _t(r.lastOut),
      r.lateMin,
      r.earlyMin,
      r.punches,
    ].join(','));
  }
  return sb.toString();
}

/// One month, one row per teacher: the totals a principal asks for.
String monthCsv(AttendanceBook book, DateTime month, String Function(int) facultyName) {
  final sb = StringBuffer('\uFEFF');
  sb.writeln('Month,${_q('${kMonthShort[month.month - 1]} ${month.year}')}');
  sb.writeln('Device ID,Teacher ID,Teacher,Subject,Duty days,Present,Late,Absent,On leave,Late (min),Early out (min),No log-out,Hours worked,Attendance %');
  for (final t in book.teachers) {
    final m = book.month(t, month);
    sb.writeln([
      t.id,
      _q(t.teacherNo),
      _q(t.name),
      _q(facultyName(t.faculty)),
      m.scheduledDays,
      m.present,
      m.late,
      m.absent,
      m.leave,
      m.lateMin,
      m.earlyMin,
      m.missedOut,
      (m.workedMin / 60).toStringAsFixed(1),
      m.rate == null ? '' : (m.rate! * 100).round(),
    ].join(','));
  }
  return sb.toString();
}

/// Daily Time Record for one teacher and one month: every calendar day, with the
/// scheduled time, what the device recorded, and the late / early-out minutes.
String dtrCsv(AttendanceBook book, Teacher t, DateTime month, String subject, String school) {
  final sb = StringBuffer('\uFEFF');
  sb.writeln('DAILY TIME RECORD');
  sb.writeln('School,${_q(school)}');
  sb.writeln('Teacher,${_q(t.name)}');
  sb.writeln('Teacher ID,${_q(t.teacherNo)}');
  sb.writeln('Position,${_q(t.position)}');
  sb.writeln('Subject,${_q(subject)}');
  sb.writeln('Month,${_q('${kMonthShort[month.month - 1]} ${month.year}')}');
  sb.writeln('All times are Philippine time (UTC+8)');
  sb.writeln();
  sb.writeln('Date,Day,Scheduled,Status,In,Out,Late (min),Early out (min),Hours');
  final last = DateTime(month.year, month.month + 1, 0).day;
  for (var d = 1; d <= last; d++) {
    final date = DateTime(month.year, month.month, d);
    final r = book.recordFor(t, date);
    if (r == null) continue;
    final status = r.status == DayStatus.leave ? 'On leave: ${r.leaveType ?? ''}' : statusLabel(r.status);
    sb.writeln([
      fmtDate(date),
      kWeekdayShort[date.weekday % 7],
      _q(r.schedule),
      _q(r.status == DayStatus.noData ? '' : status),
      _t(r.in1),
      _t(r.lastOut),
      r.lateMin,
      r.earlyMin,
      r.workedMin == 0 ? '' : (r.workedMin / 60).toStringAsFixed(2),
    ].join(','));
  }
  final m = book.month(t, month);
  sb.writeln();
  sb.writeln('Duty days,${m.scheduledDays}');
  sb.writeln('Present,${m.present}');
  sb.writeln('Late,${m.late},${m.lateMin} min');
  sb.writeln('Absent,${m.absent}');
  sb.writeln('On leave,${m.leave}');
  sb.writeln('Early out,${m.earlyMin} min');
  sb.writeln('Hours worked,${(m.workedMin / 60).toStringAsFixed(1)}');
  return sb.toString();
}

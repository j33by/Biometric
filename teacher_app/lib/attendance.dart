// Turns a teacher's schedule + their punches into what the phone shows for each day.
// The late / early rules live in schedule_calc.dart, shared byte-for-byte with the
// desktop app, so the phone and the admin's computer can never disagree.

import 'models.dart';
import 'ph.dart';
import 'schedule_calc.dart';

enum DayState {
  present, // logged in on time
  late, // logged in after the shift start
  absent, // had duty, device has data for that day, no punch
  leave, // excused
  off, // no duty that day
  waiting, // today, duty not over, nothing punched yet
  upcoming, // a future day with duty
  noData, // had duty but the device log for that day was never downloaded
}

String stateLabel(DayState s) {
  switch (s) {
    case DayState.present:
      return 'Present';
    case DayState.late:
      return 'Late';
    case DayState.absent:
      return 'Absent';
    case DayState.leave:
      return 'On leave';
    case DayState.off:
      return 'No class';
    case DayState.waiting:
      return 'Not logged in yet';
    case DayState.upcoming:
      return 'Upcoming';
    case DayState.noData:
      return 'Not synced';
  }
}

class DayView {
  final DateTime day;
  final DayState state;
  final ShiftRow? shift;
  final DayTimes? times;
  final String? leaveType;
  final List<DateTime> punches; // ascending, as recorded
  const DayView(this.day, this.state, this.shift, this.times, this.leaveType, this.punches);

  String get schedule => (shift == null || shift!.isEmpty) ? '' : shift!.label;
  bool get attended => state == DayState.present || state == DayState.late;
  DateTime? get inTime => times?.in1;
  DateTime? get outTime => times?.lastOut;
  int get lateMin => times?.lateMin ?? 0;
  int get earlyMin => times?.earlyMin ?? 0;
  bool get missedOut => attended && (times?.missedOut ?? false);

  /// Minutes between log-in and last log-out.
  int get workedMin {
    final a = inTime, b = outTime;
    if (a == null || b == null) return 0;
    final d = b.difference(a).inMinutes;
    return d > 0 ? d : 0;
  }
}

/// Everything the phone needs to explain a teacher's day.
class MySchedule {
  final int teacherId;
  final FacultyRow? faculty;
  final Map<int, ShiftRow> shifts;
  final RulesRow rules;
  final List<LeaveRow> leaves;
  const MySchedule(this.teacherId, this.faculty, this.shifts, this.rules, this.leaves);

  String get subject => (faculty == null || faculty!.name.trim().isEmpty) ? '' : faculty!.name;

  /// Shift on a given date (weekday index 0 = Sunday), or null when there is no duty.
  ShiftRow? shiftOn(DateTime day) {
    final f = faculty;
    if (f == null) return null;
    final no = f.week[day.weekday % 7];
    if (no == 0) return null;
    final s = shifts[no];
    return (s == null || s.isEmpty) ? null : s;
  }

  LeaveRow? leaveOn(DateTime day) {
    for (final l in leaves) {
      if (l.teacherId == teacherId && l.covers(day)) return l;
    }
    return null;
  }

  /// [punches] are this teacher's punches on [day]. [loggedDay] is true when the device has
  /// any punches at all that day (so a missing punch means absent, not "never downloaded").
  /// [now] is Philippine time.
  DayView view(DateTime day, List<DateTime> punches, bool loggedDay, DateTime now) {
    final d = dayOf(day);
    final today = dayOf(now);
    final shift = shiftOn(d);
    final sorted = [...punches]..sort();
    final t = calcDay(shift: shift?.times, rules: rules.values, rawPunches: sorted);

    if (t != null) {
      // a punch on a no-duty day is just recorded, never late
      final state = shift == null ? DayState.present : (t.lateMin > 0 ? DayState.late : DayState.present);
      return DayView(d, state, shift, t, null, sorted);
    }
    if (shift == null) return DayView(d, DayState.off, null, null, null, sorted);

    final leave = leaveOn(d);
    if (leave != null) return DayView(d, DayState.leave, shift, null, leave.type, sorted);
    if (d.isAfter(today)) return DayView(d, DayState.upcoming, shift, null, null, sorted);

    if (d == today) {
      final end = shift.times.endMin ?? 0;
      final nowMin = now.hour * 60 + now.minute;
      if (nowMin <= end) return DayView(d, DayState.waiting, shift, null, null, sorted);
    }
    return DayView(d, loggedDay ? DayState.absent : DayState.noData, shift, null, null, sorted);
  }
}

/// Plain-English line for today's card: what to do next.
String nextStep(DayView v, DateTime now, RulesRow rules) {
  final s = v.shift;
  if (s == null || s.isEmpty) return v.state == DayState.leave ? 'You are on leave today.' : 'No class today.';
  final start = s.times.startMin ?? 0, end = s.times.endMin ?? 0;
  final nowMin = now.hour * 60 + now.minute;
  switch (v.state) {
    case DayState.upcoming:
      return 'Duty starts ${fmtHm12(start)}.';
    case DayState.leave:
      return 'You are on leave (${v.leaveType ?? 'leave'}).';
    case DayState.waiting:
      if (nowMin < start) {
        final m = start - nowMin;
        return 'Log in at ${fmtHm12(start)} · in ${m >= 60 ? fmtMinutes(m) : '$m min'}.';
      }
      return nowMin <= start + rules.lateAllow
          ? 'Log in now. Your duty started at ${fmtHm12(start)}.'
          : 'No log-in recorded yet. The device log may not be downloaded yet.';
    case DayState.present:
    case DayState.late:
      if (v.outTime != null && nowMin >= end) return 'Done for today. Logged out ${fTime.format(v.outTime!)}.';
      if (nowMin < end) return 'Log out after ${fmtHm12(end)}.';
      return 'No log-out recorded yet. Remember to scan when you leave.';
    case DayState.absent:
      return 'No punch recorded for your ${fmtHm12(start)} – ${fmtHm12(end)} duty.';
    case DayState.noData:
      return 'Waiting for the school to download the device log.';
    case DayState.off:
      return 'No class today.';
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:cnhs_teacher_app/attendance.dart';
import 'package:cnhs_teacher_app/models.dart';
import 'package:cnhs_teacher_app/ph.dart';

// Mejorada (Research 12): Mon/Tue/Thu 7:50-9:50, Fri 10:00-12:00, Wed off.
MySchedule _mejorada({List<LeaveRow> leaves = const [], int lateAllow = 0}) => MySchedule(
      4,
      const FacultyRow(1, 'Research 12', [0, 1, 1, 0, 1, 2, 0]),
      const {
        1: ShiftRow(1, '07:50', '09:50', '', '', '', ''),
        2: ShiftRow(2, '10:00', '12:00', '', '', '', ''),
      },
      RulesRow('CNHS', lateAllow, 0, 3),
      leaves,
    );

DateTime _t(String s) => DateTime.parse(s.replaceFirst(' ', 'T'));

void main() {
  test('on time, late, and the Friday shift', () {
    final s = _mejorada();
    final now = DateTime(2026, 11, 6, 20, 0);
    var v = s.view(DateTime(2026, 11, 2), [_t('2026-11-02 07:48:00'), _t('2026-11-02 09:51:00')], true, now);
    expect(v.state, DayState.present);
    expect(v.schedule, '7:50 – 9:50 AM');
    v = s.view(DateTime(2026, 11, 3), [_t('2026-11-03 08:05:00'), _t('2026-11-03 09:40:00')], true, now);
    expect(v.state, DayState.late);
    expect(v.lateMin, 15);
    expect(v.earlyMin, 10);
    v = s.view(DateTime(2026, 11, 6), [_t('2026-11-06 10:00:00')], true, now);
    expect(v.schedule, '10:00 AM – 12:00 PM');
    expect(v.missedOut, true);
  });

  test('absent only when the device has data for that day', () {
    final s = _mejorada();
    final now = DateTime(2026, 11, 6, 20, 0);
    expect(s.view(DateTime(2026, 11, 2), [], true, now).state, DayState.absent);
    expect(s.view(DateTime(2026, 11, 2), [], false, now).state, DayState.noData);
    expect(s.view(DateTime(2026, 11, 4), [], true, now).state, DayState.off); // Wednesday
    expect(s.view(DateTime(2026, 11, 8), [], true, now).state, DayState.off); // Sunday
  });

  test('leave excuses an absence; a punch on leave still counts', () {
    final lv = [LeaveRow('a', 4, DateTime(2026, 11, 2), DateTime(2026, 11, 3), 'Sick leave', '')];
    final s = _mejorada(leaves: lv);
    final now = DateTime(2026, 11, 6, 20, 0);
    final v = s.view(DateTime(2026, 11, 2), [], true, now);
    expect(v.state, DayState.leave);
    expect(v.leaveType, 'Sick leave');
    expect(s.view(DateTime(2026, 11, 3), [_t('2026-11-03 07:50:00'), _t('2026-11-03 09:50:00')], true, now).state, DayState.present);
  });

  test('today: waiting, then upcoming for tomorrow', () {
    final s = _mejorada();
    final mon = DateTime(2026, 11, 2);
    expect(s.view(mon, [], false, DateTime(2026, 11, 2, 7, 30)).state, DayState.waiting);
    expect(s.view(mon, [], true, DateTime(2026, 11, 2, 9, 0)).state, DayState.waiting);
    expect(s.view(mon, [], true, DateTime(2026, 11, 2, 12, 0)).state, DayState.absent);
    expect(s.view(DateTime(2026, 11, 3), [], true, DateTime(2026, 11, 2, 12, 0)).state, DayState.upcoming);
  });

  test('next-step text', () {
    final s = _mejorada();
    final mon = DateTime(2026, 11, 2);
    final rules = s.rules;
    var now = DateTime(2026, 11, 2, 7, 20);
    expect(nextStep(s.view(mon, [], false, now), now, rules), 'Log in at 7:50 AM · in 30 min.');
    now = DateTime(2026, 11, 2, 8, 30);
    expect(nextStep(s.view(mon, [_t('2026-11-02 07:49:00')], true, now), now, rules), 'Log out after 9:50 AM.');
    now = DateTime(2026, 11, 2, 10, 30);
    expect(nextStep(s.view(mon, [_t('2026-11-02 07:49:00'), _t('2026-11-02 09:52:00')], true, now), now, rules), 'Done for today. Logged out 9:52 AM.');
    expect(nextStep(s.view(DateTime(2026, 11, 4), [], true, now), now, rules), 'No class today.');
  });

  test('Philippine time ignores the phone zone', () {
    expect(phNow(DateTime.utc(2026, 11, 3, 18, 30)), DateTime(2026, 11, 4, 2, 30));
    expect(phToday(DateTime.utc(2026, 11, 3, 16, 0)), DateTime(2026, 11, 4));
    expect(normalizeTimeInput('1:00 PM'), '13:00');
    expect(normalizeTimeInput('7:50 am'), '07:50');
    expect(normalizeTimeInput('13:00'), '13:00');
    expect(normalizeTimeInput('99'), null);
    expect(fmtRange12('15:00', '16:00'), '3:00 – 4:00 PM');
  });
}

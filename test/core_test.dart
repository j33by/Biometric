import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:attendance_console/core/attendance.dart';
import 'package:attendance_console/core/dates.dart';
import 'package:attendance_console/core/device_files.dart';
import 'package:attendance_console/core/models.dart';
import 'package:attendance_console/core/ph_time.dart';
import 'package:attendance_console/core/reports.dart';
import 'package:attendance_console/core/seed.dart';

final _form = File('test/fixtures/Employee_Form.xls').readAsBytesSync();
final _logs = File('test/fixtures/Attendance_Logs.txt').readAsBytesSync();

AttendanceBook _starterBook(List<PunchLog> logs, {List<LeaveRecord> leaves = const [], Rules? rules}) {
  final s = cnhsG12AbmStarter(DateTime(2026, 1, 1));
  final by = <String, List<PunchLog>>{};
  for (final l in logs) {
    by.putIfAbsent(fmtDate(l.time), () => []).add(l);
  }
  return AttendanceBook(
    teachers: s.teachers,
    faculty: {for (final f in s.faculty) f.no: f},
    shifts: {for (final x in s.shifts) x.no: x},
    rules: rules ?? Rules(),
    logsByDate: by,
    leaves: leaves,
  );
}

PunchLog _p(int id, String t) => PunchLog(teacherId: id, name: 'x', dept: 'x', time: parseDateTime(t)!, deviceId: 1);

void main() {
  test('reads the device Employee Form', () {
    final f = readDeviceForm(_form);
    expect(f.teachers.length, 4);
    expect(f.teachers.first.name, 'abc');
    expect(f.rulesFound, true);
    expect(f.rules.company, 'cnhs');
    expect(f.shifts[0].in1, '08:00');
    expect(f.faculty[0].name, 'ICT');
  });

  test('unchanged round trip keeps every teacher and rule', () {
    final f = readDeviceForm(_form);
    final out = writeDeviceForm(_form, teachers: f.teachers, faculty: f.faculty, shifts: f.shifts, rules: f.rules);
    final g = readDeviceForm(out);
    expect(g.teachers.map((s) => s.name).toList(), f.teachers.map((s) => s.name).toList());
    expect(g.rules.repeatMin, f.rules.repeatMin);
    expect(g.faculty[1].name, f.faculty[1].name);
  });

  test('added, edited and deleted teachers are written', () {
    final f = readDeviceForm(_form);
    final ts = [...f.teachers.where((s) => s.id != 2), Teacher(id: 9, name: 'Juan Dela Cruz', faculty: 3, authority: 1)];
    final out = writeDeviceForm(_form, teachers: ts);
    final g = readDeviceForm(out);
    expect(g.teachers.map((s) => s.id).toList(), [1, 3, 4, 9]);
    expect(g.teachers.last.name, 'Juan Dela Cruz');
    expect(g.teachers.last.authority, 1);
    final out2 = writeDeviceForm(out, teachers: [...ts, Teacher(id: 10, name: 'Maria')]);
    expect(readDeviceForm(out2).teachers.length, 5);
  });

  test('log import is idempotent by (id, time, device)', () {
    final a = parseAttendanceLogs(decodeLogBytes(_logs));
    expect(a.logs.length, 7);
    expect(a.badLines, 0);
    final keys = <String>{};
    for (final l in [...a.logs, ...parseAttendanceLogs(decodeLogBytes(_logs)).logs]) {
      keys.add(l.key);
    }
    expect(keys.length, 7);
  });

  test('late/early match the device report (148 / 232 minutes)', () {
    final f = readDeviceForm(_form);
    final logs = parseAttendanceLogs(decodeLogBytes(_logs)).logs.take(4).toList();
    final by = <String, List<PunchLog>>{};
    for (final l in logs) {
      by.putIfAbsent(fmtDate(l.time), () => []).add(l);
    }
    final book = AttendanceBook(
      teachers: f.teachers,
      faculty: {for (final s in f.faculty) s.no: s},
      shifts: {for (final s in f.shifts) s.no: s},
      rules: f.rules,
      logsByDate: by,
    );
    final r = book.day(DateTime(2026, 11, 2)).first;
    expect(r.lateMin, 148);
    expect(r.earlyMin, 232);
    expect(r.status, DayStatus.late);
  });

  // ------------------------------------------------------------ class program (photo)

  test('starter schedule matches the G12 ABM class program', () {
    final s = cnhsG12AbmStarter(DateTime(2026, 1, 1));
    expect(s.teachers.map((t) => '${t.id} ${t.name}').toList(), [
      '4 Mejorada, Daisy G.',
      '5 Ruloma, Rosana P.',
      '6 Labrador, Alicia C.',
      '7 Sanchez, Ishajane B.',
      '8 Pulmano, Jeremae T.',
    ]);
    final shifts = {for (final x in s.shifts) x.no: x};
    final fac = {for (final f in s.faculty) f.no: f};
    String at(int deviceId, int weekday) {
      final t = s.teachers.firstWhere((t) => t.id == deviceId);
      final no = fac[t.faculty]!.week[weekday];
      return no == 0 ? 'off' : shifts[no]!.label;
    }

    // Mon=1 .. Fri=5, straight from the photo
    expect([for (var d = 1; d <= 5; d++) at(4, d)], ['7:50 – 9:50 AM', '7:50 – 9:50 AM', 'off', '7:50 – 9:50 AM', '10:00 AM – 12:00 PM']);
    expect([for (var d = 1; d <= 5; d++) at(5, d)], ['10:00 AM – 12:00 PM', '3:00 – 4:00 PM', '1:00 – 3:00 PM', '1:00 – 3:00 PM', '8:50 – 9:50 AM']);
    expect([for (var d = 1; d <= 5; d++) at(6, d)], ['1:00 – 3:00 PM', '1:00 – 3:00 PM', '10:00 AM – 12:00 PM', '10:00 AM – 12:00 PM', 'off']);
    expect([for (var d = 1; d <= 5; d++) at(7, d)], ['3:00 – 4:00 PM', '10:00 AM – 12:00 PM', '7:50 – 9:50 AM', '3:00 – 4:00 PM', '1:00 – 3:00 PM']);
    expect([for (var d = 1; d <= 5; d++) at(8, d)], ['off', 'off', 'off', 'off', '7:50 – 8:50 AM']);
    for (final id in [4, 5, 6, 7, 8]) {
      expect(at(id, 0), 'off');
      expect(at(id, 6), 'off');
    }
    // SHS ARAL: Mon + Tue 4-5 PM, nobody assigned (the photo names no teacher)
    expect(shifts[fac[5]!.week[1]]!.label, '4:00 – 5:00 PM');
    expect(s.teachers.any((t) => t.faculty == 5), false);
    // the four full-load teachers teach 8 hours a week, the adviser 1
    int hours(int deviceId) {
      final t = s.teachers.firstWhere((t) => t.id == deviceId);
      var m = 0;
      for (var d = 0; d < 7; d++) {
        final no = fac[t.faculty]!.week[d];
        if (no != 0) m += shifts[no]!.dutyMinutes;
      }
      return m ~/ 60;
    }

    expect([for (final id in [4, 5, 6, 7]) hours(id)], [8, 8, 8, 8]);
    expect(hours(8), 1);
  });

  test('the school device file: only the three known mistakes differ from the starter', () {
    final f = readDeviceForm(File('test/fixtures/CNHS_Employee_Form.xls').readAsBytesSync());
    final s = cnhsG12AbmStarter(DateTime(2026, 1, 1));
    expect(f.teachers.where((t) => t.id >= 4 && t.id <= 8).map((t) => t.id).toList(), [4, 5, 6, 7, 8]);
    // weekly patterns agree slot by slot, except HGP (Pulmano had no day)
    for (final fs in s.faculty.where((x) => x.name.isNotEmpty)) {
      final file = f.faculty[fs.no - 1];
      expect(file.name, fs.name);
      if (fs.no != 6) expect(file.week, fs.week);
    }
    expect(f.faculty[5].week, [0, 0, 0, 0, 0, 0, 0]);
    // shifts agree except the afternoon ones saved as 01:00 / 03:00 / 04:00, and HGP 07:00
    for (final no in [1, 2, 7]) {
      expect('${f.shifts[no - 1].in1}-${f.shifts[no - 1].out1}', '${s.shifts[no - 1].in1}-${s.shifts[no - 1].out1}');
    }
    expect(f.shifts[2].in1, '01:00'); // 1 AM on a 24-hour device
    expect(s.shifts[2].in1, '13:00');
    expect(f.shifts[5].in1, '07:00');
    expect(s.shifts[5].in1, '07:50');
  });

  test('starter data survives the device Employee Form', () {
    final s = cnhsG12AbmStarter(DateTime(2026, 1, 1));
    final out = writeDeviceForm(_form, teachers: s.teachers, faculty: s.faculty, shifts: s.shifts, rules: Rules(company: 'CNHS', repeatMin: 3));
    final g = readDeviceForm(out);
    expect(g.teachers.map((t) => t.name).toList(), s.teachers.map((t) => t.name).toList());
    expect(g.teachers.map((t) => t.id).toList(), [4, 5, 6, 7, 8]);
    expect(g.teachers.map((t) => t.faculty).toList(), [1, 2, 3, 4, 6]);
    expect(g.shifts[0].in1, '07:50');
    expect(g.shifts[2].in1, '13:00');
    expect(g.shifts[3].out1, '16:00');
    expect(g.faculty[0].name, 'Research 12');
    expect(g.faculty[0].week, [0, 1, 1, 0, 1, 2, 0]);
    expect(g.faculty[1].week, [0, 2, 4, 3, 3, 7, 0]);
    expect(g.faculty[5].week, [0, 0, 0, 0, 0, 6, 0]);
    // and onto the school's own file, keeping the people already on the device
    final school = File('test/fixtures/CNHS_Employee_Form.xls').readAsBytesSync();
    final keep = readDeviceForm(school).teachers.where((t) => t.id < 4 && t.name.isNotEmpty).toList();
    final out2 = writeDeviceForm(school, teachers: [...keep, ...s.teachers], faculty: s.faculty, shifts: s.shifts, rules: Rules(company: 'CNHS'));
    final h = readDeviceForm(out2);
    expect(h.teachers.map((t) => t.id).toList(), [1, 2, 3, 4, 5, 6, 7, 8]);
    expect(h.shifts[2].in1, '13:00');
  });

  test('teacher attendance follows the shift of the day (Philippine time)', () {
    // Monday 2 Nov 2026
    final book = _starterBook([
      _p(4, '2026-11-02 07:48:10'), _p(4, '2026-11-02 09:52:00'), // Mejorada: on time, out after 9:50
      _p(5, '2026-11-02 10:07:00'), _p(5, '2026-11-02 12:01:00'), // Ruloma 10:00-12:00, 7 min late
      _p(7, '2026-11-02 15:00:00'), // Sanchez 3-4 PM, in only
      // Labrador (1-3 PM) has nothing -> absent, because others punched
    ]);
    final d = DateTime(2026, 11, 2);
    final r = {for (final x in book.day(d)) x.teacher.id: x};
    expect(r[4]!.status, DayStatus.present);
    expect(r[4]!.lateMin, 0);
    expect(r[4]!.schedule, '7:50 – 9:50 AM');
    expect(r[5]!.status, DayStatus.late);
    expect(r[5]!.lateMin, 7);
    expect(r[7]!.missedOut, true);
    expect(r[6]!.status, DayStatus.absent);
    expect(r[8]!.status, DayStatus.dayOff); // Pulmano only has Friday
    final sum = book.summary(d);
    expect([sum.expected, sum.present, sum.late, sum.absent], [4, 3, 1, 1]);
  });

  test('Friday: Ruloma 8:50, Pulmano 7:50, Mejorada 10:00', () {
    final book = _starterBook([
      _p(8, '2026-11-06 07:45:00'), _p(8, '2026-11-06 08:50:00'),
      _p(5, '2026-11-06 08:55:00'), _p(5, '2026-11-06 09:50:00'),
    ]);
    final r = {for (final x in book.day(DateTime(2026, 11, 6))) x.teacher.id: x};
    expect(r[8]!.status, DayStatus.present);
    expect(r[8]!.schedule, '7:50 – 8:50 AM');
    expect(r[5]!.status, DayStatus.late);
    expect(r[5]!.lateMin, 5);
    expect(r[4]!.status, DayStatus.absent); // Mejorada 10-12, nothing yet
  });

  test('left early is measured against the shift end', () {
    final book = _starterBook([_p(6, '2026-11-02 12:55:00'), _p(6, '2026-11-02 14:20:00')]);
    final r = book.recordFor(book.teachers.firstWhere((t) => t.id == 6), DateTime(2026, 11, 2))!;
    expect(r.status, DayStatus.present);
    expect(r.earlyMin, 40);
  });

  test('late allowance is honoured', () {
    final logs = [_p(4, '2026-11-02 07:56:00'), _p(4, '2026-11-02 09:50:00')];
    DayRecord mej(AttendanceBook b) => b.recordFor(b.teachers.first, DateTime(2026, 11, 2))!;
    expect(mej(_starterBook(logs, rules: Rules(lateAllow: 0))).status, DayStatus.late);
    expect(mej(_starterBook(logs, rules: Rules(lateAllow: 10))).status, DayStatus.present);
  });

  test('a day with no imported data is "no data", not absent', () {
    final book = _starterBook([]);
    expect(book.day(DateTime(2026, 11, 2)).first.status, DayStatus.noData);
  });

  test('leave turns an absence into "on leave" and out of the expected count', () {
    final leave = LeaveRecord(id: 'a', teacherId: 6, from: DateTime(2026, 11, 2), to: DateTime(2026, 11, 3), type: 'Sick leave');
    final book = _starterBook([_p(4, '2026-11-02 07:50:00'), _p(4, '2026-11-02 09:50:00')], leaves: [leave]);
    final d = DateTime(2026, 11, 2);
    final lab = book.teachers.firstWhere((t) => t.id == 6);
    final r = book.recordFor(lab, d)!;
    expect(r.status, DayStatus.leave);
    expect(r.leaveType, 'Sick leave');
    final sum = book.summary(d);
    // Mejorada punched; Ruloma and Sanchez (also on duty, no punch) are absent; Labrador is excused
    expect(sum.absent, 2);
    expect(sum.onLeave, 1);
    expect(sum.expected, 3);
    // and a teacher who punched on a leave day is simply present
    final book2 = _starterBook([_p(6, '2026-11-02 13:00:00'), _p(6, '2026-11-02 15:00:00')], leaves: [leave]);
    expect(book2.recordFor(lab, d)!.status, DayStatus.present);
  });

  test('"on duty now" reads the Philippine clock', () {
    final book = _starterBook([_p(4, '2026-11-02 07:49:00')]);
    var duty = book.dutyAt(DateTime(2026, 11, 2, 7, 30));
    final up = duty.firstWhere((x) => x.teacher.id == 4);
    expect(up.phase, DutyPhase.upcoming);
    expect(up.minutesToStart, 20);
    duty = book.dutyAt(DateTime(2026, 11, 2, 10, 15));
    final ruloma = duty.firstWhere((x) => x.teacher.id == 5);
    expect(ruloma.phase, DutyPhase.onDuty);
    expect(ruloma.notInYet, true); // data exists for today, Ruloma has no punch
    expect(duty.first.phase, DutyPhase.onDuty); // on duty sorted first
    final mej = duty.firstWhere((x) => x.teacher.id == 4);
    expect(mej.phase, DutyPhase.finished);
    expect(mej.notInYet, false);
    expect(book.dutyAt(DateTime(2026, 11, 1, 9, 0)), isEmpty); // Sunday
  });

  test('month totals', () {
    final logs = <PunchLog>[];
    for (final day in ['2026-11-02', '2026-11-03']) {
      logs.add(_p(4, '$day 07:50:00'));
      logs.add(_p(4, '$day 09:50:00'));
    }
    logs.add(_p(4, '2026-11-05 08:10:00')); // Thursday, late, no out
    final book = _starterBook(logs);
    final m = book.month(book.teachers.first, DateTime(2026, 11, 15));
    expect(m.present, 3);
    expect(m.late, 1);
    expect(m.lateMin, 20);
    expect(m.missedOut, 1);
    expect(m.workedMin, 240);
    final csv = dtrCsv(book, book.teachers.first, DateTime(2026, 11, 1), 'Research 12', 'CNHS');
    expect(csv.contains('DAILY TIME RECORD'), true);
    expect(csv.contains('2026-11-05,Thu'), true);
    expect(monthCsv(book, DateTime(2026, 11, 1), (n) => 'x').split('\n').length > 5, true);
  });

  // ------------------------------------------------------------ Philippine time

  test('Philippine time does not depend on the computer zone', () {
    // 18:30 UTC on the 3rd is already 02:30 on the 4th in the Philippines
    expect(phNow(DateTime.utc(2026, 11, 3, 18, 30)), DateTime(2026, 11, 4, 2, 30));
    expect(phToday(DateTime.utc(2026, 11, 3, 16, 0)), DateTime(2026, 11, 4));
    expect(phToday(DateTime.utc(2026, 11, 3, 15, 59)), DateTime(2026, 11, 3));
  });

  test('shift times typed by an admin become 24-hour device times', () {
    expect(normalizeTimeInput('7:50 am'), '07:50');
    expect(normalizeTimeInput('1:00 PM'), '13:00');
    expect(normalizeTimeInput('12:00 AM'), '00:00');
    expect(normalizeTimeInput('15:00'), '15:00');
    expect(normalizeTimeInput('25:00'), null);
    expect(normalizeTimeInput('banana'), null);
    expect(fmtRange12('07:50', '09:50'), '7:50 – 9:50 AM');
    expect(fmtRange12('11:00', '13:00'), '11:00 AM – 1:00 PM');
  });
}

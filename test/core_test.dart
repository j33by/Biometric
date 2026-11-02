import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:attendance_console/core/attendance.dart';
import 'package:attendance_console/core/dates.dart';
import 'package:attendance_console/core/device_files.dart';
import 'package:attendance_console/core/models.dart';

final _form = File('test/fixtures/Employee_Form.xls').readAsBytesSync();
final _logs = File('test/fixtures/Attendance_Logs.txt').readAsBytesSync();

void main() {
  test('reads the device Employee Form', () {
    final f = readDeviceForm(_form);
    expect(f.students.length, 4);
    expect(f.students.first.name, 'abc');
    expect(f.rulesFound, true);
    expect(f.rules.company, 'cnhs');
    expect(f.shifts[0].in1, '08:00');
    expect(f.sections[0].name, 'ICT');
  });

  test('unchanged round trip keeps every student and rule', () {
    final f = readDeviceForm(_form);
    final out = writeDeviceForm(_form, students: f.students, sections: f.sections, shifts: f.shifts, rules: f.rules);
    final g = readDeviceForm(out);
    expect(g.students.map((s) => s.name).toList(), f.students.map((s) => s.name).toList());
    expect(g.rules.repeatMin, f.rules.repeatMin);
    expect(g.sections[1].name, f.sections[1].name);
  });

  test('added, edited and deleted students are written', () {
    final f = readDeviceForm(_form);
    final studs = [...f.students.where((s) => s.id != 2), Student(id: 9, name: 'Juan Dela Cruz', section: 3, authority: 1)];
    final out = writeDeviceForm(_form, students: studs);
    final g = readDeviceForm(out);
    expect(g.students.map((s) => s.id).toList(), [1, 3, 4, 9]);
    expect(g.students.last.name, 'Juan Dela Cruz');
    expect(g.students.last.authority, 1);
    // and a second pass over our own output still works
    final out2 = writeDeviceForm(out, students: [...studs, Student(id: 10, name: 'Maria')]);
    expect(readDeviceForm(out2).students.length, 5);
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
      students: f.students,
      sections: {for (final s in f.sections) s.no: s},
      shifts: {for (final s in f.shifts) s.no: s},
      rules: f.rules,
      logsByDate: by,
    );
    final r = book.day(DateTime(2026, 11, 2)).first;
    expect(r.lateMin, 148);
    expect(r.earlyMin, 232);
    expect(r.status, DayStatus.late);
  });
}

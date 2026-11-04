// Maps the biometric device's USB files to/from app models.
//
//   Employee Form.xls     (upload to device)   teachers, faculty, shifts, rules
//   Attendance_Logs.txt   (download from device) raw punches
//
// Layout facts were taken from a real export of this device family:
//   "Employee Form"          header row has "*ID" in column A; the row after it
//                            holds weekday formulas; teachers start 2 rows below.
//                            A: ID  B: Name  C: Department 1-16  D: Authority 0/1
//                            E..AI: 31 days of schedule (blank = use department)
//   "Attendance Rules Form"  company in D2, shifts in A5:G14, departments in
//                            H5:P20, rules in G17:G20.

import 'dart:convert';
import 'dart:typed_data';

import 'cfb.dart';
import 'dates.dart';
import 'models.dart';
import 'xls_workbook.dart';

const String kFormSheetName = 'Employee Form';
const String kRulesSheetName = 'Attendance Rules Form';

class DeviceForm {
  final List<Teacher> teachers;
  final List<Faculty> faculty;
  final List<Shift> shifts;
  final Rules rules;
  final bool rulesFound;
  final String? formDate;
  DeviceForm(this.teachers, this.faculty, this.shifts, this.rules, this.rulesFound, this.formDate);
}

class DeviceFormException implements Exception {
  final String message;
  DeviceFormException(this.message);
  @override
  String toString() => message;
}

XlsWorkbook _open(Uint8List bytes) {
  final CfbFile cfb;
  try {
    cfb = Cfb.read(bytes);
  } on FormatException catch (e) {
    throw DeviceFormException('Not a valid .xls file (${e.message})');
  }
  final wb = cfb.find('Workbook') ?? cfb.find('Book');
  if (wb == null) throw DeviceFormException('No Workbook stream inside the .xls');
  try {
    return XlsWorkbook.parse(wb.data);
  } on FormatException catch (e) {
    throw DeviceFormException('Unreadable .xls: ${e.message}');
  }
}

int _findHeaderRow(XlsSheet s) {
  for (var r = 0; r < 60; r++) {
    final t = s.text(r, 0);
    if (t != null && t.trim() == '*ID') return r;
  }
  return -1;
}

String _timeCell(XlsSheet s, int r, int c) {
  final v = s.value(r, c);
  if (v == null) return '';
  if (v is double) {
    if (v >= 0 && v < 1) return fmtHm((v * 1440).round());
    return '';
  }
  final t = (v as String).trim();
  return parseHm(t) == null ? '' : fmtHm(parseHm(t)!);
}

DeviceForm readDeviceForm(Uint8List bytes) {
  final wb = _open(bytes);
  final form = wb.sheetByName(kFormSheetName) ?? (wb.sheets.isNotEmpty ? wb.sheets[0] : null);
  if (form == null) throw DeviceFormException('Workbook has no sheets');
  final header = _findHeaderRow(form);
  if (header < 0) throw DeviceFormException('This does not look like a device Employee Form (no "*ID" column)');

  String? formDate;
  for (var r = 0; r < header; r++) {
    final label = form.text(r, 0);
    if (label != null && label.startsWith('Date(')) {
      formDate = form.text(r, 4);
    }
  }

  final teachers = <Teacher>[];
  final seen = <int>{};
  for (var r = header + 2; r <= form.lastRow; r++) {
    final id = form.number(r, 0);
    if (id == null) break;
    if (!seen.add(id.toInt())) continue;
    final sched = <double?>[];
    var any = false;
    for (var c = 4; c <= 34; c++) {
      final v = form.number(r, c);
      sched.add(v);
      if (v != null) any = true;
    }
    teachers.add(Teacher(
      id: id.toInt(),
      name: (form.text(r, 1) ?? '').trim(),
      faculty: (form.number(r, 2) ?? 1).toInt().clamp(1, 16),
      authority: (form.number(r, 3) ?? 0).toInt() == 1 ? 1 : 0,
      schedule: any ? sched : null,
    ));
  }

  final rulesSheet = wb.sheetByName(kRulesSheetName);
  final faculty = <Faculty>[];
  final shifts = <Shift>[];
  var rules = Rules();
  var found = false;
  if (rulesSheet != null && (rulesSheet.text(3, 0) ?? '').trim() == 'Shift Number') {
    found = true;
    rules = Rules(
      company: (rulesSheet.text(1, 3) ?? '').trim(),
      lateAllow: (rulesSheet.number(16, 6) ?? 0).toInt(),
      earlyAllow: (rulesSheet.number(17, 6) ?? 0).toInt(),
      repeatMin: (rulesSheet.number(18, 6) ?? 3).toInt(),
      scheduleMode: (rulesSheet.number(19, 6) ?? 0).toInt(),
    );
    for (var i = 0; i < 10; i++) {
      final r = 4 + i;
      shifts.add(Shift(
        no: i + 1,
        in1: _timeCell(rulesSheet, r, 1),
        out1: _timeCell(rulesSheet, r, 2),
        in2: _timeCell(rulesSheet, r, 3),
        out2: _timeCell(rulesSheet, r, 4),
        otIn: _timeCell(rulesSheet, r, 5),
        otOut: _timeCell(rulesSheet, r, 6),
      ));
    }
    for (var i = 0; i < 16; i++) {
      final r = 4 + i;
      final week = <int>[];
      for (var d = 0; d < 7; d++) {
        week.add((rulesSheet.number(r, 9 + d) ?? 0).toInt());
      }
      faculty.add(Faculty(no: i + 1, name: (rulesSheet.text(r, 8) ?? '').trim(), week: week));
    }
  }
  return DeviceForm(teachers, faculty, shifts, rules, found, formDate);
}

bool _sameValue(Object? a, Object? b) {
  if (a == null || (a is String && a.trim().isEmpty)) {
    return b == null || (b is String && b.trim().isEmpty);
  }
  if (a is num && b is num) return a.toDouble() == b.toDouble();
  if (a is String && b is String) return a == b;
  return false;
}

void _setIfChanged(XlsSheet s, int r, int c, Object? v, {int fallbackXf = 0}) {
  final existing = s.cell(r, c);
  if (existing != null && existing.raw == null && _sameValue(existing.value, v)) return;
  if (existing != null && existing.raw != null) return; // never touch formulas
  s.set(r, c, v, xf: existing == null ? fallbackXf : null);
}

/// Produces a new .xls from [template] (the device's own file) with the
/// given data applied.  Anything not listed below is left byte-identical.
Uint8List writeDeviceForm(
  Uint8List template, {
  required List<Teacher> teachers,
  List<Faculty>? faculty,
  List<Shift>? shifts,
  Rules? rules,
}) {
  final cfb = Cfb.read(template);
  final wbStream = cfb.find('Workbook') ?? cfb.find('Book');
  if (wbStream == null) throw DeviceFormException('Template has no Workbook stream');
  final wb = XlsWorkbook.parse(wbStream.data);

  final form = wb.sheetByName(kFormSheetName) ?? wb.sheets.first;
  final header = _findHeaderRow(form);
  if (header < 0) throw DeviceFormException('Template is not a device Employee Form');
  final dataStart = header + 2;

  // Style template: first existing teacher row, else the header row.
  final styleRow = form.rows[dataStart] ?? form.rows[header];
  final xfByCol = <int, int>{};
  if (styleRow != null) {
    styleRow.forEach((c, cell) => xfByCol[c] = cell.xf);
  }
  var maxCol = 34;
  for (final c in xfByCol.keys) {
    if (c > maxCol) maxCol = c;
  }

  form.clearRowsFrom(dataStart);
  final list = teachers.where((s) => !s.deleted).toList()..sort((a, b) => a.id.compareTo(b.id));
  for (var i = 0; i < list.length; i++) {
    final s = list[i];
    final r = dataStart + i;
    form.set(r, 0, s.id, xf: xfByCol[0] ?? 0);
    form.set(r, 1, s.name, xf: xfByCol[1] ?? 0);
    form.set(r, 2, s.faculty.clamp(1, 16), xf: xfByCol[2] ?? 0);
    form.set(r, 3, s.authority == 1 ? 1 : 0, xf: xfByCol[3] ?? 0);
    for (var c = 4; c <= maxCol; c++) {
      final v = (s.schedule != null && c - 4 < s.schedule!.length) ? s.schedule![c - 4] : null;
      form.set(r, c, v, xf: xfByCol[c] ?? xfByCol[4] ?? 0);
    }
  }

  final rs = wb.sheetByName(kRulesSheetName);
  if (rs != null && (rs.text(3, 0) ?? '').trim() == 'Shift Number') {
    if (rules != null) {
      _setIfChanged(rs, 1, 3, rules.company);
      _setIfChanged(rs, 16, 6, rules.lateAllow);
      _setIfChanged(rs, 17, 6, rules.earlyAllow);
      _setIfChanged(rs, 18, 6, rules.repeatMin);
      _setIfChanged(rs, 19, 6, rules.scheduleMode);
    }
    if (shifts != null) {
      for (final sh in shifts) {
        if (sh.no < 1 || sh.no > 10) continue;
        final r = 3 + sh.no;
        final vals = [sh.in1, sh.out1, sh.in2, sh.out2, sh.otIn, sh.otOut];
        for (var k = 0; k < 6; k++) {
          _setIfChanged(rs, r, 1 + k, vals[k], fallbackXf: rs.cell(r, 1)?.xf ?? 0);
        }
      }
    }
    if (faculty != null) {
      for (final sec in faculty) {
        if (sec.no < 1 || sec.no > 16) continue;
        final r = 3 + sec.no;
        _setIfChanged(rs, r, 8, sec.name);
        for (var d = 0; d < 7; d++) {
          _setIfChanged(rs, r, 9 + d, sec.week[d]);
        }
      }
    }
  }

  final newWb = wb.build();
  final streams = <CfbStream>[];
  for (final s in cfb.streams) {
    streams.add(identical(s, wbStream) ? CfbStream(s.name, newWb) : s);
  }
  return Cfb.write(CfbFile(streams, cfb.rootClsid));
}

// ---------------------------------------------------------------- logs

class ParsedLogs {
  final List<PunchLog> logs;
  final int badLines;
  ParsedLogs(this.logs, this.badLines);
}

String decodeLogBytes(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    final units = <int>[];
    for (var i = 2; i + 1 < bytes.length; i += 2) {
      units.add(bytes[i] | (bytes[i + 1] << 8));
    }
    return String.fromCharCodes(units);
  }
  var b = bytes;
  if (b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) {
    b = Uint8List.sublistView(b, 3);
  }
  return utf8.decode(b, allowMalformed: true);
}

/// Parses "ID \t Name \t Dept. \t Time \t Device ID" lines.
ParsedLogs parseAttendanceLogs(String text) {
  final out = <PunchLog>[];
  var bad = 0;
  for (final raw in const LineSplitter().convert(text)) {
    final line = raw.trimRight();
    if (line.trim().isEmpty) continue;
    final cols = line.split('\t');
    if (cols.length < 4) {
      bad++;
      continue;
    }
    final id = int.tryParse(cols[0].trim());
    if (id == null) {
      // header row ("ID") is expected once; anything else non-numeric is bad
      if (cols[0].trim().toUpperCase() != 'ID') bad++;
      continue;
    }
    final t = parseDateTime(cols[3]);
    if (t == null) {
      bad++;
      continue;
    }
    out.add(PunchLog(
      teacherId: id,
      name: cols[1].trim(),
      dept: cols[2].trim(),
      time: t,
      deviceId: cols.length > 4 ? (int.tryParse(cols[4].trim()) ?? 1) : 1,
    ));
  }
  return ParsedLogs(out, bad);
}

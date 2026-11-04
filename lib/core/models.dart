// Plain data classes shared by the file layer, the local store, the cloud
// client and the UI.  No Flutter imports.
//
// Vocabulary (the app says "teacher", the device says "employee"):
//   Teacher  = one person enrolled on the biometric device (device "*ID" column)
//   Faculty  = one of the device's 16 "Department" slots.  Each slot carries a
//              name (we use the SUBJECT taught) and a weekly shift pattern, so a
//              teacher's faculty slot decides when they must log in and out.
//              In the Excel file this stays called "Department" because that is
//              what the device reads; only the app says Faculty / Subject.
//   Shift    = one of the device's 10 shifts (log-in / log-out times, PH time).

import 'dates.dart';
import 'schedule_calc.dart';

class Teacher {
  int id; // device user ID (the number typed on the biometric device)
  String name;
  int faculty; // 1..16, maps to the device "Department" slot
  int authority; // 0 = teacher, 1 = device administrator
  String teacherNo; // the teacher's DepEd / employee "Teacher ID" (not the device ID)
  String position; // e.g. Teacher I, Master Teacher, Adviser
  String contact;
  String notes;
  List<double?>? schedule; // per-day overrides from the Employee Form (31 cols)
  DateTime updatedAt;
  bool deleted;

  Teacher({
    required this.id,
    required this.name,
    this.faculty = 1,
    this.authority = 0,
    this.teacherNo = '',
    this.position = '',
    this.contact = '',
    this.notes = '',
    this.schedule,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Teacher copy() => Teacher(
        id: id,
        name: name,
        faculty: faculty,
        authority: authority,
        teacherNo: teacherNo,
        position: position,
        contact: contact,
        notes: notes,
        schedule: schedule == null ? null : List<double?>.from(schedule!),
        updatedAt: updatedAt,
        deleted: deleted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'faculty': faculty,
        'authority': authority,
        'teacherNo': teacherNo,
        'position': position,
        'contact': contact,
        'notes': notes,
        'schedule': schedule,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deleted': deleted,
      };

  factory Teacher.fromJson(Map<String, dynamic> j) => Teacher(
        id: (j['id'] as num).toInt(),
        name: (j['name'] ?? '') as String,
        // 'section' is the key older (student) databases used
        faculty: ((j['faculty'] ?? j['section'] ?? 1) as num).toInt(),
        authority: ((j['authority'] ?? 0) as num).toInt(),
        teacherNo: (j['teacherNo'] ?? '') as String,
        position: (j['position'] ?? '') as String,
        contact: (j['contact'] ?? '') as String,
        notes: (j['notes'] ?? '') as String,
        schedule: j['schedule'] == null
            ? null
            : (j['schedule'] as List).map((e) => (e as num?)?.toDouble()).toList(),
        updatedAt: DateTime.tryParse((j['updatedAt'] ?? '') as String)?.toLocal() ?? DateTime.now(),
        deleted: (j['deleted'] ?? false) as bool,
      );
}

/// A device "Department" slot (1..16) used as a teacher's faculty schedule.
/// [name] is the subject taught; it is what the device prints in the logs.
class Faculty {
  int no;
  String name;
  List<int> week; // shift number for Sun..Sat, 0 = no duty
  DateTime updatedAt;

  Faculty({required this.no, required this.name, List<int>? week, DateTime? updatedAt})
      : week = week ?? List<int>.filled(7, 1),
        updatedAt = updatedAt ?? DateTime.now();

  Faculty copy() => Faculty(no: no, name: name, week: List<int>.from(week), updatedAt: updatedAt);

  Map<String, dynamic> toJson() => {
        'no': no,
        'name': name,
        'week': week,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory Faculty.fromJson(Map<String, dynamic> j) => Faculty(
        no: (j['no'] as num).toInt(),
        name: (j['name'] ?? '') as String,
        week: ((j['week'] ?? List<int>.filled(7, 1)) as List).map((e) => (e as num).toInt()).toList(),
        updatedAt: DateTime.tryParse((j['updatedAt'] ?? '') as String)?.toLocal() ?? DateTime.now(),
      );
}

/// One of the 10 device shifts.  Times are 24-hour "HH:mm" Philippine time, or empty.
class Shift {
  int no;
  String in1, out1, in2, out2, otIn, otOut;
  DateTime updatedAt;

  Shift({
    required this.no,
    this.in1 = '',
    this.out1 = '',
    this.in2 = '',
    this.out2 = '',
    this.otIn = '',
    this.otOut = '',
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Shift copy() => Shift(
      no: no, in1: in1, out1: out1, in2: in2, out2: out2, otIn: otIn, otOut: otOut, updatedAt: updatedAt);

  bool get isEmpty => in1.isEmpty && out1.isEmpty;
  bool get hasSecondPeriod => in2.isNotEmpty && out2.isNotEmpty;
  bool get hasOvertime => otIn.isNotEmpty && otOut.isNotEmpty;

  ShiftTimes get times => ShiftTimes(in1: in1, out1: out1, in2: in2, out2: out2, otIn: otIn, otOut: otOut);

  /// "7:50 – 9:50 AM" (or both periods), what people read.
  String get label {
    if (isEmpty) return '–';
    final a = fmtRange12(in1, out1);
    return hasSecondPeriod ? '$a, ${fmtRange12(in2, out2)}' : a;
  }

  /// Minutes of duty this shift represents.
  int get dutyMinutes {
    int span(String a, String b) {
      final x = parseHm(a), y = parseHm(b);
      return (x == null || y == null || y <= x) ? 0 : y - x;
    }

    return span(in1, out1) + (hasSecondPeriod ? span(in2, out2) : 0);
  }

  Map<String, dynamic> toJson() => {
        'no': no,
        'in1': in1,
        'out1': out1,
        'in2': in2,
        'out2': out2,
        'otIn': otIn,
        'otOut': otOut,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory Shift.fromJson(Map<String, dynamic> j) => Shift(
        no: (j['no'] as num).toInt(),
        in1: (j['in1'] ?? '') as String,
        out1: (j['out1'] ?? '') as String,
        in2: (j['in2'] ?? '') as String,
        out2: (j['out2'] ?? '') as String,
        otIn: (j['otIn'] ?? '') as String,
        otOut: (j['otOut'] ?? '') as String,
        updatedAt: DateTime.tryParse((j['updatedAt'] ?? '') as String)?.toLocal() ?? DateTime.now(),
      );
}

class Rules {
  String company;
  int lateAllow; // minutes
  int earlyAllow; // minutes
  int repeatMin; // repeated verification window, minutes
  int scheduleMode; // 0 = by department (faculty), 1 = by employee
  // How many minutes to ADD to every punch read from the device so it matches
  // Philippine time.  0 when the device clock is right.  Kept in the app and the
  // cloud only: the device's own Excel file has no cell for it.
  int clockOffsetMin;
  DateTime updatedAt;

  Rules({
    this.company = '',
    this.lateAllow = 0,
    this.earlyAllow = 0,
    this.repeatMin = 3,
    this.scheduleMode = 0,
    this.clockOffsetMin = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Rules copy() => Rules(
      company: company,
      lateAllow: lateAllow,
      earlyAllow: earlyAllow,
      repeatMin: repeatMin,
      scheduleMode: scheduleMode,
      clockOffsetMin: clockOffsetMin,
      updatedAt: updatedAt);

  RuleValues get values => RuleValues(lateAllow: lateAllow, earlyAllow: earlyAllow, repeatMin: repeatMin);

  Map<String, dynamic> toJson() => {
        'company': company,
        'lateAllow': lateAllow,
        'earlyAllow': earlyAllow,
        'repeatMin': repeatMin,
        'scheduleMode': scheduleMode,
        'clockOffsetMin': clockOffsetMin,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory Rules.fromJson(Map<String, dynamic> j) => Rules(
        company: (j['company'] ?? '') as String,
        lateAllow: ((j['lateAllow'] ?? 0) as num).toInt(),
        earlyAllow: ((j['earlyAllow'] ?? 0) as num).toInt(),
        repeatMin: ((j['repeatMin'] ?? 3) as num).toInt(),
        scheduleMode: ((j['scheduleMode'] ?? 0) as num).toInt(),
        clockOffsetMin: ((j['clockOffsetMin'] ?? 0) as num).toInt(),
        updatedAt: DateTime.tryParse((j['updatedAt'] ?? '') as String)?.toLocal() ?? DateTime.now(),
      );
}

const List<String> kLeaveTypes = [
  'Sick leave',
  'Vacation leave',
  'Official business',
  'Training / seminar',
  'Personal',
  'Other',
];

/// An excused absence.  A scheduled day with no punches that falls inside a
/// leave is shown as "On leave" and is NOT counted as absent.
class LeaveRecord {
  String id;
  int teacherId; // device ID
  DateTime from; // date only, inclusive
  DateTime to; // date only, inclusive
  String type;
  String note;
  DateTime updatedAt;
  bool deleted;

  LeaveRecord({
    required this.id,
    required this.teacherId,
    required DateTime from,
    required DateTime to,
    this.type = 'Sick leave',
    this.note = '',
    DateTime? updatedAt,
    this.deleted = false,
  })  : from = dateOnly(from),
        to = dateOnly(to),
        updatedAt = updatedAt ?? DateTime.now();

  bool covers(DateTime day) {
    final d = dateOnly(day);
    return !d.isBefore(from) && !d.isAfter(to);
  }

  int get days => to.difference(from).inDays + 1;

  LeaveRecord copy() => LeaveRecord(
      id: id, teacherId: teacherId, from: from, to: to, type: type, note: note, updatedAt: updatedAt, deleted: deleted);

  Map<String, dynamic> toJson() => {
        'id': id,
        'teacherId': teacherId,
        'from': fmtDate(from),
        'to': fmtDate(to),
        'type': type,
        'note': note,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deleted': deleted,
      };

  factory LeaveRecord.fromJson(Map<String, dynamic> j) => LeaveRecord(
        id: j['id'].toString(),
        teacherId: (j['teacherId'] as num).toInt(),
        from: parseDate(j['from'] as String) ?? DateTime.now(),
        to: parseDate(j['to'] as String) ?? DateTime.now(),
        type: (j['type'] ?? 'Other') as String,
        note: (j['note'] ?? '') as String,
        updatedAt: DateTime.tryParse((j['updatedAt'] ?? '') as String)?.toLocal() ?? DateTime.now(),
        deleted: (j['deleted'] ?? false) as bool,
      );
}

/// One raw punch from the device.  Identity = (teacherId, time, deviceId),
/// which is what makes re-importing the same USB export idempotent.
class PunchLog {
  final int teacherId;
  final String name;
  final String dept; // what the device prints in "Dept." = the faculty slot name = the subject
  final DateTime time;
  final int deviceId;

  PunchLog({
    required this.teacherId,
    required this.name,
    required this.dept,
    required this.time,
    required this.deviceId,
  });

  String get key => '$teacherId|${fmtDateTime(time)}|$deviceId';

  Map<String, dynamic> toJson() => {
        'i': teacherId,
        'n': name,
        'd': dept,
        't': fmtDateTime(time),
        'v': deviceId,
      };

  factory PunchLog.fromJson(Map<String, dynamic> j) => PunchLog(
        teacherId: (j['i'] as num).toInt(),
        name: (j['n'] ?? '') as String,
        dept: (j['d'] ?? '') as String,
        time: parseDateTime(j['t'] as String)!,
        deviceId: ((j['v'] ?? 1) as num).toInt(),
      );
}

class AdminUser {
  final String id;
  final String email;
  final String name;
  final String role; // superadmin | admin | viewer
  final bool disabled;

  const AdminUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    this.disabled = false,
  });

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id'].toString(),
        email: (j['email'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        role: (j['role'] ?? 'admin') as String,
        disabled: (j['disabled'] ?? false) as bool,
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'email': email, 'name': name, 'role': role, 'disabled': disabled};

  bool get canWrite => role == 'superadmin' || role == 'admin';
  bool get isSuper => role == 'superadmin';
}

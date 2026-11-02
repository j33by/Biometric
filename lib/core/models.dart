// Plain data classes shared by the file layer, the local store, the cloud
// client and the UI.  No Flutter imports.

import 'dates.dart';

class Student {
  int id; // device user ID (the number typed on the biometric device)
  String name;
  int section; // 1..16, maps to the device "Department" slot
  int authority; // 0 = student, 1 = device administrator
  String lrn;
  String contact;
  String notes;
  List<double?>? schedule; // per-day overrides from the Employee Form (31 cols)
  DateTime updatedAt;
  bool deleted;

  Student({
    required this.id,
    required this.name,
    this.section = 1,
    this.authority = 0,
    this.lrn = '',
    this.contact = '',
    this.notes = '',
    this.schedule,
    DateTime? updatedAt,
    this.deleted = false,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Student copy() => Student(
        id: id,
        name: name,
        section: section,
        authority: authority,
        lrn: lrn,
        contact: contact,
        notes: notes,
        schedule: schedule == null ? null : List<double?>.from(schedule!),
        updatedAt: updatedAt,
        deleted: deleted,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'section': section,
        'authority': authority,
        'lrn': lrn,
        'contact': contact,
        'notes': notes,
        'schedule': schedule,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
        'deleted': deleted,
      };

  factory Student.fromJson(Map<String, dynamic> j) => Student(
        id: (j['id'] as num).toInt(),
        name: (j['name'] ?? '') as String,
        section: ((j['section'] ?? 1) as num).toInt(),
        authority: ((j['authority'] ?? 0) as num).toInt(),
        lrn: (j['lrn'] ?? '') as String,
        contact: (j['contact'] ?? '') as String,
        notes: (j['notes'] ?? '') as String,
        schedule: j['schedule'] == null
            ? null
            : (j['schedule'] as List).map((e) => (e as num?)?.toDouble()).toList(),
        updatedAt: DateTime.tryParse((j['updatedAt'] ?? '') as String)?.toLocal() ?? DateTime.now(),
        deleted: (j['deleted'] ?? false) as bool,
      );
}

/// A device "Department" slot (1..16) used here as a class section.
class Section {
  int no;
  String name;
  List<int> week; // shift number for Sun..Sat, 0 = holiday
  DateTime updatedAt;

  Section({required this.no, required this.name, List<int>? week, DateTime? updatedAt})
      : week = week ?? List<int>.filled(7, 1),
        updatedAt = updatedAt ?? DateTime.now();

  Section copy() => Section(no: no, name: name, week: List<int>.from(week), updatedAt: updatedAt);

  Map<String, dynamic> toJson() => {
        'no': no,
        'name': name,
        'week': week,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory Section.fromJson(Map<String, dynamic> j) => Section(
        no: (j['no'] as num).toInt(),
        name: (j['name'] ?? '') as String,
        week: ((j['week'] ?? List<int>.filled(7, 1)) as List).map((e) => (e as num).toInt()).toList(),
        updatedAt: DateTime.tryParse((j['updatedAt'] ?? '') as String)?.toLocal() ?? DateTime.now(),
      );
}

/// One of the 10 device shifts.  Times are "HH:mm" or empty.
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
  int scheduleMode; // 0 = by department, 1 = by employee
  DateTime updatedAt;

  Rules({
    this.company = '',
    this.lateAllow = 0,
    this.earlyAllow = 0,
    this.repeatMin = 3,
    this.scheduleMode = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  Rules copy() => Rules(
      company: company,
      lateAllow: lateAllow,
      earlyAllow: earlyAllow,
      repeatMin: repeatMin,
      scheduleMode: scheduleMode,
      updatedAt: updatedAt);

  Map<String, dynamic> toJson() => {
        'company': company,
        'lateAllow': lateAllow,
        'earlyAllow': earlyAllow,
        'repeatMin': repeatMin,
        'scheduleMode': scheduleMode,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory Rules.fromJson(Map<String, dynamic> j) => Rules(
        company: (j['company'] ?? '') as String,
        lateAllow: ((j['lateAllow'] ?? 0) as num).toInt(),
        earlyAllow: ((j['earlyAllow'] ?? 0) as num).toInt(),
        repeatMin: ((j['repeatMin'] ?? 3) as num).toInt(),
        scheduleMode: ((j['scheduleMode'] ?? 0) as num).toInt(),
        updatedAt: DateTime.tryParse((j['updatedAt'] ?? '') as String)?.toLocal() ?? DateTime.now(),
      );
}

/// One raw punch from the device.  Identity = (studentId, time, deviceId),
/// which is what makes re-importing the same USB export idempotent.
class PunchLog {
  final int studentId;
  final String name;
  final String dept;
  final DateTime time;
  final int deviceId;

  PunchLog({
    required this.studentId,
    required this.name,
    required this.dept,
    required this.time,
    required this.deviceId,
  });

  String get key => '$studentId|${fmtDateTime(time)}|$deviceId';

  Map<String, dynamic> toJson() => {
        'i': studentId,
        'n': name,
        'd': dept,
        't': fmtDateTime(time),
        'v': deviceId,
      };

  factory PunchLog.fromJson(Map<String, dynamic> j) => PunchLog(
        studentId: (j['i'] as num).toInt(),
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

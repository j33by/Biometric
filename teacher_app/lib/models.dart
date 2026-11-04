import 'ph.dart';
import 'schedule_calc.dart';

class TeacherRow {
  final int id; // device ID
  final String name;
  final int faculty;
  final String position;
  const TeacherRow(this.id, this.name, this.faculty, [this.position = '']);

  factory TeacherRow.fromJson(Map<String, dynamic> j) => TeacherRow(
        (j['id'] as num).toInt(),
        (j['name'] ?? '') as String,
        ((j['faculty'] ?? 1) as num).toInt(),
        (j['position'] ?? '') as String,
      );
}

/// One account <-> teacher binding request.
class Link {
  final String id;
  final String userId;
  final String email;
  final String accountName; // name shown for the account (admin-editable)
  final String teacherName; // current name of the bound teacher record
  final String status; // pending | approved | denied
  final String adminNote;
  final int teacherId; // device ID
  final int? faculty;
  final String teacherNo; // the teacher's DepEd / employee Teacher ID
  final String position;
  final DateTime createdAt;
  final bool unlinkRequested;
  final String unlinkReason;

  const Link({
    required this.id,
    required this.userId,
    required this.email,
    required this.accountName,
    required this.teacherName,
    required this.status,
    required this.adminNote,
    required this.teacherId,
    required this.faculty,
    required this.teacherNo,
    required this.position,
    required this.createdAt,
    this.unlinkRequested = false,
    this.unlinkReason = '',
  });

  factory Link.fromJson(Map<String, dynamic> j) {
    final s = j['teachers'] as Map<String, dynamic>?; // null until approved (RLS)
    return Link(
      id: j['id'] as String,
      userId: j['user_id'] as String,
      email: (j['email'] ?? '') as String,
      accountName: (j['account_name'] ?? '') as String,
      teacherName: ((s?['name']) ?? j['teacher_name'] ?? '') as String,
      status: j['status'] as String,
      adminNote: (j['admin_note'] ?? '') as String,
      teacherId: (j['teacher_id'] as num).toInt(),
      faculty: (s?['faculty'] as num?)?.toInt(),
      teacherNo: ((s?['teacher_no']) ?? '') as String,
      position: ((s?['position']) ?? '') as String,
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      unlinkRequested: (j['unlink_requested'] ?? false) as bool,
      unlinkReason: (j['unlink_reason'] ?? '') as String,
    );
  }

  String get displayName => accountName.isNotEmpty ? accountName : teacherName;
}

class Notice {
  final int id;
  final String title;
  final String body;
  final bool pinned;
  final int? faculty;
  final DateTime createdAt;

  const Notice(this.id, this.title, this.body, this.pinned, this.faculty, this.createdAt);

  factory Notice.fromJson(Map<String, dynamic> j) => Notice(
        (j['id'] as num).toInt(),
        (j['title'] ?? '') as String,
        (j['body'] ?? '') as String,
        (j['pinned'] ?? false) as bool,
        (j['faculty'] as num?)?.toInt(),
        DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

// ------------------------------------------------------------------ schedule data

class ShiftRow {
  final int no;
  final String in1, out1, in2, out2, otIn, otOut;
  const ShiftRow(this.no, this.in1, this.out1, this.in2, this.out2, this.otIn, this.otOut);

  factory ShiftRow.fromJson(Map<String, dynamic> j) => ShiftRow(
        (j['no'] as num).toInt(),
        (j['in1'] ?? '') as String,
        (j['out1'] ?? '') as String,
        (j['in2'] ?? '') as String,
        (j['out2'] ?? '') as String,
        (j['ot_in'] ?? '') as String,
        (j['ot_out'] ?? '') as String,
      );

  ShiftTimes get times => ShiftTimes(in1: in1, out1: out1, in2: in2, out2: out2, otIn: otIn, otOut: otOut);
  bool get isEmpty => in1.isEmpty && out1.isEmpty;

  String get label {
    if (isEmpty) return '–';
    final a = fmtRange12(in1, out1);
    return (in2.isNotEmpty && out2.isNotEmpty) ? '$a, ${fmtRange12(in2, out2)}' : a;
  }
}

class FacultyRow {
  final int no;
  final String name; // the subject
  final List<int> week; // Sun..Sat shift numbers, 0 = no duty
  const FacultyRow(this.no, this.name, this.week);

  factory FacultyRow.fromJson(Map<String, dynamic> j) => FacultyRow(
        (j['no'] as num).toInt(),
        (j['name'] ?? '') as String,
        ((j['week'] ?? const [0, 1, 1, 1, 1, 1, 0]) as List).map((e) => (e as num).toInt()).toList(),
      );
}

class LeaveRow {
  final String id;
  final int teacherId;
  final DateTime from, to;
  final String type, note;
  const LeaveRow(this.id, this.teacherId, this.from, this.to, this.type, this.note);

  factory LeaveRow.fromJson(Map<String, dynamic> j) => LeaveRow(
        j['id'].toString(),
        (j['teacher_id'] as num).toInt(),
        dayOf(DateTime.parse(j['from_date'] as String)),
        dayOf(DateTime.parse(j['to_date'] as String)),
        (j['type'] ?? 'Other') as String,
        (j['note'] ?? '') as String,
      );

  bool covers(DateTime d) {
    final x = dayOf(d);
    return !x.isBefore(from) && !x.isAfter(to);
  }
}

class RulesRow {
  final String company;
  final int lateAllow, earlyAllow, repeatMin;
  const RulesRow(this.company, this.lateAllow, this.earlyAllow, this.repeatMin);

  factory RulesRow.fromJson(Map<String, dynamic>? j) => j == null
      ? const RulesRow('', 0, 0, 3)
      : RulesRow((j['company'] ?? '') as String, ((j['late_allow'] ?? 0) as num).toInt(),
          ((j['early_allow'] ?? 0) as num).toInt(), ((j['repeat_min'] ?? 3) as num).toInt());

  RuleValues get values => RuleValues(lateAllow: lateAllow, earlyAllow: earlyAllow, repeatMin: repeatMin);
}

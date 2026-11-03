class StudentRow {
  final int id;
  final String name;
  final int section;
  const StudentRow(this.id, this.name, this.section);

  factory StudentRow.fromJson(Map<String, dynamic> j) => StudentRow(
        (j['id'] as num).toInt(),
        (j['name'] ?? '') as String,
        ((j['section'] ?? 1) as num).toInt(),
      );
}

/// One account <-> student binding request.
class Link {
  final String id;
  final String userId;
  final String email;
  final String accountName; // name shown for the account (admin-editable)
  final String studentName; // current name of the bound student record
  final String status; // pending | approved | denied
  final String adminNote;
  final int studentId;
  final int? section;
  final String lrn;
  final DateTime createdAt;
  final bool unlinkRequested;
  final String unlinkReason;

  const Link({
    required this.id,
    required this.userId,
    required this.email,
    required this.accountName,
    required this.studentName,
    required this.status,
    required this.adminNote,
    required this.studentId,
    required this.section,
    required this.lrn,
    required this.createdAt,
    this.unlinkRequested = false,
    this.unlinkReason = '',
  });

  factory Link.fromJson(Map<String, dynamic> j) {
    final s = j['students'] as Map<String, dynamic>?; // null until approved (RLS)
    return Link(
      id: j['id'] as String,
      userId: j['user_id'] as String,
      email: (j['email'] ?? '') as String,
      accountName: (j['account_name'] ?? '') as String,
      studentName: ((s?['name']) ?? j['student_name'] ?? '') as String,
      status: j['status'] as String,
      adminNote: (j['admin_note'] ?? '') as String,
      studentId: (j['student_id'] as num).toInt(),
      section: (s?['section'] as num?)?.toInt(),
      lrn: ((s?['lrn']) ?? '') as String,
      createdAt: DateTime.parse(j['created_at'] as String).toLocal(),
      unlinkRequested: (j['unlink_requested'] ?? false) as bool,
      unlinkReason: (j['unlink_reason'] ?? '') as String,
    );
  }

  String get displayName => accountName.isNotEmpty ? accountName : studentName;
}

class Notice {
  final int id;
  final String title;
  final String body;
  final bool pinned;
  final int? section;
  final DateTime createdAt;

  const Notice(this.id, this.title, this.body, this.pinned, this.section, this.createdAt);

  factory Notice.fromJson(Map<String, dynamic> j) => Notice(
        (j['id'] as num).toInt(),
        (j['title'] ?? '') as String,
        (j['body'] ?? '') as String,
        (j['pinned'] ?? false) as bool,
        (j['section'] as num?)?.toInt(),
        DateTime.parse(j['created_at'] as String).toLocal(),
      );
}

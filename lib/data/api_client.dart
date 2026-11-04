// Thin client for the Render-hosted API (which fronts Supabase).

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/dates.dart';
import '../core/models.dart';

class ApiException implements Exception {
  final int? status;
  final String message;
  ApiException(this.message, [this.status]);

  bool get isAuth => status == 401 || status == 403;
  bool get isNetwork => status == null;

  @override
  String toString() => message;
}

class SnapshotData {
  final List<Teacher> teachers;
  final List<Faculty> faculty;
  final List<Shift> shifts;
  final List<LeaveRecord> leaves;
  final Rules? rules;
  SnapshotData(this.teachers, this.faculty, this.shifts, this.leaves, this.rules);
}

class LogPage {
  final List<PunchLog> logs;
  final int cursor; // server-side bigint id of the last row returned
  final bool hasMore;
  LogPage(this.logs, this.cursor, this.hasMore);
}

/// A phone-app login (Supabase Auth) and the teacher record it is, or asks to be, bound to.
class TeacherAccount {
  final String id;
  final String email;
  final String accountName; // name shown for the account (admin-editable)
  final String pickedName; // the name the teacher picked when asking
  final String status; // pending | approved | denied
  final String adminNote;
  final int teacherId; // device ID of the bound record
  final String teacherName; // current name of that record
  final bool teacherMissing; // the record was removed from the cloud
  final int? faculty;
  final String teacherNo;
  final String position;
  final DateTime? createdAt; // real instant (UTC)
  final bool unlinkRequested;
  final String unlinkReason;

  const TeacherAccount({
    required this.id,
    required this.email,
    required this.accountName,
    required this.pickedName,
    required this.status,
    required this.adminNote,
    required this.teacherId,
    required this.teacherName,
    required this.teacherMissing,
    required this.faculty,
    required this.teacherNo,
    required this.position,
    required this.createdAt,
    required this.unlinkRequested,
    required this.unlinkReason,
  });

  factory TeacherAccount.fromJson(Map<String, dynamic> j) => TeacherAccount(
        id: j['id'].toString(),
        email: (j['email'] ?? '') as String,
        accountName: (j['accountName'] ?? '') as String,
        pickedName: (j['pickedName'] ?? '') as String,
        status: (j['status'] ?? 'pending') as String,
        adminNote: (j['adminNote'] ?? '') as String,
        teacherId: (j['teacherId'] as num).toInt(),
        teacherName: (j['teacherName'] ?? '') as String,
        teacherMissing: (j['teacherMissing'] ?? false) as bool,
        faculty: (j['faculty'] as num?)?.toInt(),
        teacherNo: (j['teacherNo'] ?? '') as String,
        position: (j['position'] ?? '') as String,
        createdAt: DateTime.tryParse((j['createdAt'] ?? '') as String),
        unlinkRequested: (j['unlinkRequested'] ?? false) as bool,
        unlinkReason: (j['unlinkReason'] ?? '') as String,
      );

  String get displayName {
    if (accountName.trim().isNotEmpty) return accountName.trim();
    if (email.isNotEmpty) return email;
    return teacherName;
  }
}

/// An announcement shown to teachers in the phone app.
class NoticeItem {
  final int id;
  final String title;
  final String body;
  final int? faculty; // null = every teacher
  final bool pinned;
  final DateTime? createdAt; // real instant (UTC)

  const NoticeItem({
    required this.id,
    required this.title,
    required this.body,
    required this.faculty,
    required this.pinned,
    required this.createdAt,
  });

  factory NoticeItem.fromJson(Map<String, dynamic> j) => NoticeItem(
        id: (j['id'] as num).toInt(),
        title: (j['title'] ?? '') as String,
        body: (j['body'] ?? '') as String,
        faculty: (j['faculty'] as num?)?.toInt(),
        pinned: (j['pinned'] ?? false) as bool,
        createdAt: DateTime.tryParse((j['createdAt'] ?? '') as String),
      );
}

/// A phone-app login that has the admin screens (a row in Supabase `app_admins`).
class PhoneAdmin {
  final String userId;
  final String email;
  const PhoneAdmin(this.userId, this.email);

  factory PhoneAdmin.fromJson(Map<String, dynamic> j) =>
      PhoneAdmin(j['userId'].toString(), (j['email'] ?? '') as String);
}

class ApiClient {
  String baseUrl;
  String? token;
  final http.Client _http = http.Client();

  ApiClient({this.baseUrl = '', this.token});

  bool get configured => baseUrl.trim().isNotEmpty;

  String get _base {
    var b = baseUrl.trim();
    while (b.endsWith('/')) {
      b = b.substring(0, b.length - 1);
    }
    return b;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Duration timeout = const Duration(seconds: 25),
    Map<String, String>? query,
  }) async {
    if (!configured) throw ApiException('Server URL is not set');
    final uri = Uri.parse('$_base/api$path').replace(queryParameters: query);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final streamed = await _http.send(req).timeout(timeout);
      res = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw ApiException('Server did not respond in time (a free Render server needs ~50 s to wake up)');
    } catch (e) {
      throw ApiException('Cannot reach server: $e');
    }
    dynamic parsed;
    if (res.body.isNotEmpty) {
      try {
        parsed = jsonDecode(res.body);
      } catch (_) {
        parsed = null;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return parsed;
    final msg = (parsed is Map && parsed['error'] != null) ? parsed['error'].toString() : 'HTTP ${res.statusCode}';
    throw ApiException(msg, res.statusCode);
  }

  // ---------------------------------------------------------------- auth

  Future<AdminUser> login(String email, String password) async {
    final j = await _send('POST', '/auth/login',
        body: {'email': email.trim(), 'password': password}, timeout: const Duration(seconds: 75));
    token = j['token'] as String;
    return AdminUser.fromJson(j['admin'] as Map<String, dynamic>);
  }

  Future<AdminUser> me() async {
    final j = await _send('GET', '/auth/me');
    return AdminUser.fromJson(j['admin'] as Map<String, dynamic>);
  }

  /// Philippine time according to the server (UTC+8, computed from its UTC clock),
  /// or null if unreachable. Used to catch a computer whose clock or zone is wrong.
  Future<DateTime?> serverPhTime() async {
    try {
      final j = await _send('GET', '/health', timeout: const Duration(seconds: 75));
      final s = (j is Map ? j['phTime'] : null) as String?;
      return s == null ? null : parseDateTime(s);
    } catch (_) {
      return null;
    }
  }

  Future<bool> health() async {
    try {
      await _send('GET', '/health', timeout: const Duration(seconds: 75));
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------- data

  Future<SnapshotData> snapshot() async {
    final j = await _send('GET', '/sync/snapshot', timeout: const Duration(seconds: 60));
    return SnapshotData(
      ((j['teachers'] ?? []) as List).map((e) => Teacher.fromJson(e as Map<String, dynamic>)).toList(),
      ((j['faculty'] ?? []) as List).map((e) => Faculty.fromJson(e as Map<String, dynamic>)).toList(),
      ((j['shifts'] ?? []) as List).map((e) => Shift.fromJson(e as Map<String, dynamic>)).toList(),
      ((j['leaves'] ?? []) as List).map((e) => LeaveRecord.fromJson(e as Map<String, dynamic>)).toList(),
      j['rules'] == null ? null : Rules.fromJson(j['rules'] as Map<String, dynamic>),
    );
  }

  Future<void> push({
    List<Teacher> teachers = const [],
    List<Faculty> faculty = const [],
    List<Shift> shifts = const [],
    List<LeaveRecord> leaves = const [],
    Rules? rules,
  }) async {
    await _send('POST', '/sync/push',
        body: {
          'teachers': teachers.map((e) => e.toJson()).toList(),
          'faculty': faculty.map((e) => e.toJson()).toList(),
          'shifts': shifts.map((e) => e.toJson()).toList(),
          'leaves': leaves.map((e) => e.toJson()).toList(),
          if (rules != null) 'rules': rules.toJson(),
        },
        timeout: const Duration(seconds: 60));
  }

  Future<int> pushLogs(List<PunchLog> logs) async {
    final j = await _send(
        'POST',
        '/logs/bulk',
        body: {
          'logs': logs
              .map((l) => {
                    'teacherId': l.teacherId,
                    'name': l.name,
                    'dept': l.dept,
                    'time': l.toJson()['t'],
                    'deviceId': l.deviceId,
                  })
              .toList()
        },
        timeout: const Duration(seconds: 90));
    return ((j['inserted'] ?? 0) as num).toInt();
  }

  Future<LogPage> pullLogs(int after, {int limit = 5000}) async {
    final j = await _send('GET', '/logs',
        query: {'after': '$after', 'limit': '$limit'}, timeout: const Duration(seconds: 90));
    final rows = (j['logs'] ?? []) as List;
    final logs = <PunchLog>[];
    for (final r in rows) {
      final m = r as Map<String, dynamic>;
      logs.add(PunchLog.fromJson({
        'i': m['teacherId'],
        'n': m['name'],
        'd': m['dept'],
        't': m['time'],
        'v': m['deviceId'],
      }));
    }
    return LogPage(logs, ((j['cursor'] ?? after) as num).toInt(), (j['hasMore'] ?? false) as bool);
  }

  // -------------------------------------------------------------- admins

  Future<List<AdminUser>> listAdmins() async {
    final j = await _send('GET', '/admins');
    return ((j['admins'] ?? []) as List).map((e) => AdminUser.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> createAdmin(String email, String name, String password, String role) =>
      _send('POST', '/admins', body: {'email': email, 'name': name, 'password': password, 'role': role});

  Future<void> updateAdmin(String id, {String? name, String? role, String? password, bool? disabled}) =>
      _send('PATCH', '/admins/$id', body: {
        if (name != null) 'name': name,
        if (role != null) 'role': role,
        if (password != null) 'password': password,
        if (disabled != null) 'disabled': disabled,
      });

  Future<void> deleteAdmin(String id) => _send('DELETE', '/admins/$id');

  // ------------------------------------------------------ teacher accounts

  Future<List<TeacherAccount>> listAccounts() async {
    final j = await _send('GET', '/accounts', timeout: const Duration(seconds: 60));
    return ((j['accounts'] ?? []) as List).map((e) => TeacherAccount.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Approve / deny / revoke ([status]), rename the account, bind to another teacher
  /// ([teacherId]) or rename the teacher record ([teacherName]). Send only what changes.
  Future<void> updateAccount(String id,
          {String? status, int? teacherId, String? accountName, String? note, String? teacherName}) =>
      _send('PATCH', '/accounts/$id', body: {
        if (status != null) 'status': status,
        if (teacherId != null) 'teacherId': teacherId,
        if (accountName != null) 'accountName': accountName,
        if (note != null) 'note': note,
        if (teacherName != null) 'teacherName': teacherName,
      });

  /// Answer a teacher's request to unlink: approve deletes the link, otherwise it stays.
  Future<void> resolveUnlink(String id, bool approve, {String note = ''}) =>
      _send('POST', '/accounts/$id/unlink', body: {'approve': approve, 'note': note});

  // ------------------------------------------------------------- notices

  Future<List<NoticeItem>> listNotices() async {
    final j = await _send('GET', '/notices');
    return ((j['notices'] ?? []) as List).map((e) => NoticeItem.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> addNotice(String title, String body, {int? faculty, bool pinned = false}) =>
      _send('POST', '/notices', body: {'title': title, 'body': body, 'faculty': faculty, 'pinned': pinned});

  Future<void> deleteNotice(int id) => _send('DELETE', '/notices/$id');

  // -------------------------------------------------------- phone admins

  Future<List<PhoneAdmin>> listPhoneAdmins() async {
    final j = await _send('GET', '/phone-admins', timeout: const Duration(seconds: 60));
    return ((j['admins'] ?? []) as List).map((e) => PhoneAdmin.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> addPhoneAdmin(String email) => _send('POST', '/phone-admins', body: {'email': email});

  Future<void> removePhoneAdmin(String userId) => _send('DELETE', '/phone-admins/$userId');
}

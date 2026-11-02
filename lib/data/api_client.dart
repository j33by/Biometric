// Thin client for the Render-hosted API (which fronts Supabase).

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

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
  final List<Student> students;
  final List<Section> sections;
  final List<Shift> shifts;
  final Rules? rules;
  SnapshotData(this.students, this.sections, this.shifts, this.rules);
}

class LogPage {
  final List<PunchLog> logs;
  final int cursor; // server-side bigint id of the last row returned
  final bool hasMore;
  LogPage(this.logs, this.cursor, this.hasMore);
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
      ((j['students'] ?? []) as List).map((e) => Student.fromJson(e as Map<String, dynamic>)).toList(),
      ((j['sections'] ?? []) as List).map((e) => Section.fromJson(e as Map<String, dynamic>)).toList(),
      ((j['shifts'] ?? []) as List).map((e) => Shift.fromJson(e as Map<String, dynamic>)).toList(),
      j['rules'] == null ? null : Rules.fromJson(j['rules'] as Map<String, dynamic>),
    );
  }

  Future<void> push({
    List<Student> students = const [],
    List<Section> sections = const [],
    List<Shift> shifts = const [],
    Rules? rules,
  }) async {
    await _send('POST', '/sync/push',
        body: {
          'students': students.map((e) => e.toJson()).toList(),
          'sections': sections.map((e) => e.toJson()).toList(),
          'shifts': shifts.map((e) => e.toJson()).toList(),
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
                    'studentId': l.studentId,
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
        'i': m['studentId'],
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
}

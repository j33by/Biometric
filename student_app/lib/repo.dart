import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'models.dart';
import 'notify.dart';

SupabaseClient get sb => Supabase.instance.client;

final _ts = DateFormat('yyyy-MM-dd HH:mm:ss');
const _linkSelect = '*, students(name, section, lrn)';

/// All server calls. Permissions are enforced by row level security in
/// supabase/student_app.sql, not here.
class Repo {
  static String get uid => sb.auth.currentUser!.id;

  static Future<bool> isAdmin() async => (await sb.rpc('is_app_admin')) == true;

  // ------------------------------------------------------------ student
  static Future<Link?> myLink() async {
    final r = await sb.from('student_links').select(_linkSelect).eq('user_id', uid).maybeSingle();
    return r == null ? null : Link.fromJson(r);
  }

  static Future<List<StudentRow>> search(String q) async {
    final r = await sb.rpc('search_students', params: {'q': q}) as List;
    return r.map((e) => StudentRow.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Sends (or re-sends after a denial) a binding request.
  static Future<void> request(StudentRow s, String accountName) async {
    await sb.from('student_links').delete().eq('user_id', uid); // RLS: only non-approved rows go
    await sb.from('student_links').insert({
      'user_id': uid,
      'student_id': s.id,
      'student_name': s.name,
      'account_name': accountName.trim(),
      'email': sb.auth.currentUser?.email ?? '',
    });
  }

  static Future<void> requestUnlink(String reason) async {
    await sb.rpc('request_unlink', params: {'p_reason': reason});
  }

  static Future<void> cancelUnlink() async {
    await sb.rpc('cancel_unlink_request');
  }

  static Future<void> cancelRequest() async {
    await sb.from('student_links').delete().eq('user_id', uid);
  }

  /// Punch times in [from, to), newest first.
  static Future<List<DateTime>> logs(int studentId, DateTime from, DateTime to) async {
    final r = await sb
        .from('attendance_logs')
        .select('punched_at')
        .eq('student_id', studentId)
        .gte('punched_at', _ts.format(from))
        .lt('punched_at', _ts.format(to))
        .order('punched_at', ascending: false)
        .limit(3000);
    return r.map((e) => DateTime.parse(e['punched_at'] as String)).toList(); // device wall-clock, no zone
  }

  static Future<List<Notice>> notices({int limit = 50}) async {
    final r = await sb
        .from('notices')
        .select()
        .order('pinned', ascending: false)
        .order('created_at', ascending: false)
        .limit(limit);
    return r.map(Notice.fromJson).toList();
  }

  /// Notices newer than [id], oldest first (used by background notifications).
  static Future<List<Notice>> noticesAfter(int id) async {
    final r = await sb.from('notices').select().gt('id', id).order('id').limit(20);
    return r.map(Notice.fromJson).toList();
  }

  static Future<int> latestNoticeId() async {
    final r = await sb.from('notices').select('id').order('id', ascending: false).limit(1);
    return r.isEmpty ? 0 : (r.first['id'] as num).toInt();
  }

  static Future<Map<int, String>>? _sec;
  static Future<Map<int, String>> sections() => _sec ??= _loadSections();
  static Future<Map<int, String>> _loadSections() async {
    final r = await sb.from('sections').select('no, name');
    return {for (final e in r) (e['no'] as num).toInt(): (e['name'] ?? '') as String};
  }

  // ------------------------------------------------------------ admin
  /// status: pending | approved | denied, or 'unlink' for approved links with an open unlink request.
  static Future<List<Link>> links(String status) async {
    var f = sb.from('student_links').select(_linkSelect);
    f = status == 'unlink' ? f.eq('status', 'approved').eq('unlink_requested', true) : f.eq('status', status);
    final r = await f.order('created_at', ascending: false);
    return r.map(Link.fromJson).toList();
  }

  static Future<void> resolveUnlink(String id, bool approve, {String note = ''}) async {
    await sb.rpc('admin_resolve_unlink', params: {'p_id': id, 'p_approve': approve, 'p_note': note});
  }

  static Future<void> review(String id, String status,
      {int? studentId, String? accountName, String? note}) async {
    await sb.rpc('admin_review_link', params: {
      'p_id': id,
      'p_status': status,
      'p_student_id': studentId,
      'p_account_name': accountName,
      'p_note': note,
    });
  }

  static Future<List<StudentRow>> students(String q) async {
    var f = sb.from('students').select('id, name, section').eq('deleted', false);
    if (q.trim().isNotEmpty) f = f.ilike('name', '%${q.trim()}%');
    final r = await f.order('name').limit(60);
    return r.map(StudentRow.fromJson).toList();
  }

  static Future<void> renameStudent(int id, String name) async {
    await sb.rpc('admin_rename_student', params: {'p_id': id, 'p_name': name});
  }

  static Future<void> addNotice(String title, String body, {int? section, bool pinned = false}) async {
    await sb.from('notices').insert({'title': title, 'body': body, 'section': section, 'pinned': pinned});
  }

  static Future<void> deleteNotice(int id) async {
    await sb.from('notices').delete().eq('id', id);
  }
}

String errText(Object e) {
  final m = e is PostgrestException ? e.message : e.toString();
  if (m.contains('one_approved_per_student')) return 'That student record is already linked to another approved account.';
  if (m.contains('student_links_user_id_key')) return 'You already have a request. Pull to refresh.';
  return m;
}

/// Always sign out through this so this phone stops receiving the user's notifications.
Future<void> signOut() async {
  await Notify.stop();
  await sb.auth.signOut();
}

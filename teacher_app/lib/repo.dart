import 'package:supabase_flutter/supabase_flutter.dart';

import 'attendance.dart';
import 'models.dart';
import 'notify.dart';
import 'ph.dart';

SupabaseClient get sb => Supabase.instance.client;

const _linkSelect = '*, teachers(name, faculty, teacher_no, position)';

/// All server calls. Permissions are enforced by row level security in
/// supabase/teacher_app.sql, not here.
///
/// Every date/time that crosses this class is Philippine wall-clock time (see ph.dart):
/// punches are stored as written by the device, with no zone.
class Repo {
  static String get uid => sb.auth.currentUser!.id;

  static Future<bool> isAdmin() async => (await sb.rpc('is_app_admin')) == true;

  // ------------------------------------------------------------ teacher
  static Future<Link?> myLink() async {
    final r = await sb.from('teacher_links').select(_linkSelect).eq('user_id', uid).maybeSingle();
    return r == null ? null : Link.fromJson(r);
  }

  static Future<List<TeacherRow>> search(String q) async {
    final r = await sb.rpc('search_teachers', params: {'q': q}) as List;
    return r.map((e) => TeacherRow.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Sends (or re-sends after a denial) a binding request.
  static Future<void> request(TeacherRow s, String accountName) async {
    await sb.from('teacher_links').delete().eq('user_id', uid); // RLS: only non-approved rows go
    await sb.from('teacher_links').insert({
      'user_id': uid,
      'teacher_id': s.id,
      'teacher_name': s.name,
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
    await sb.from('teacher_links').delete().eq('user_id', uid);
  }

  /// Punch times in [from, to), newest first. Philippine wall-clock, no zone.
  static Future<List<DateTime>> logs(int teacherId, DateTime from, DateTime to) async {
    final r = await sb
        .from('attendance_logs')
        .select('punched_at')
        .eq('teacher_id', teacherId)
        .gte('punched_at', fStampSql.format(from))
        .lt('punched_at', fStampSql.format(to))
        .order('punched_at', ascending: false)
        .limit(3000);
    return r.map((e) => DateTime.parse(e['punched_at'] as String)).toList();
  }

  /// Dates in [from, to] on which the device has any punches at all.
  static Future<Set<DateTime>> loggedDays(DateTime from, DateTime to) async {
    final r = await sb.rpc('logged_days', params: {'p_from': fDate.format(from), 'p_to': fDate.format(to)}) as List;
    return r.map((e) => dayOf(DateTime.parse(e.toString()))).toSet();
  }

  /// The teacher's own schedule: faculty slot + shifts + rules + leaves.
  static Future<MySchedule> mySchedule(Link l) async {
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      sb.from('faculty').select(),
      sb.from('shifts').select(),
      sb.from('rules').select().eq('id', 1).maybeSingle(),
      sb.from('leaves').select().eq('teacher_id', l.teacherId).eq('deleted', false),
    ]);
    final fac = (results[0] as List).map((e) => FacultyRow.fromJson(e as Map<String, dynamic>)).toList();
    final sh = (results[1] as List).map((e) => ShiftRow.fromJson(e as Map<String, dynamic>)).toList();
    final lv = (results[3] as List).map((e) => LeaveRow.fromJson(e as Map<String, dynamic>)).toList();
    return MySchedule(
      l.teacherId,
      fac.where((f) => f.no == l.faculty).firstOrNull,
      {for (final s in sh) s.no: s},
      RulesRow.fromJson(results[2] as Map<String, dynamic>?),
      lv,
    );
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

  static Future<Map<int, String>>? _fac;
  static Future<Map<int, String>> facultyNames() => _fac ??= _loadFaculty();
  static Future<Map<int, String>> _loadFaculty() async {
    final r = await sb.from('faculty').select('no, name');
    return {for (final e in r) (e['no'] as num).toInt(): (e['name'] ?? '') as String};
  }

  // ------------------------------------------------------------ admin
  /// status: pending | approved | denied, or 'unlink' for approved links with an open unlink request.
  static Future<List<Link>> links(String status) async {
    var f = sb.from('teacher_links').select(_linkSelect);
    f = status == 'unlink' ? f.eq('status', 'approved').eq('unlink_requested', true) : f.eq('status', status);
    final r = await f.order('created_at', ascending: false);
    return r.map(Link.fromJson).toList();
  }

  static Future<void> resolveUnlink(String id, bool approve, {String note = ''}) async {
    await sb.rpc('admin_resolve_unlink', params: {'p_id': id, 'p_approve': approve, 'p_note': note});
  }

  static Future<void> review(String id, String status, {int? teacherId, String? accountName, String? note}) async {
    await sb.rpc('admin_review_link', params: {
      'p_id': id,
      'p_status': status,
      'p_teacher_id': teacherId,
      'p_account_name': accountName,
      'p_note': note,
    });
  }

  static Future<List<TeacherRow>> teachers(String q) async {
    var f = sb.from('teachers').select('id, name, faculty, position').eq('deleted', false);
    if (q.trim().isNotEmpty) f = f.ilike('name', '%${q.trim()}%');
    final r = await f.order('name').limit(100);
    return r.map(TeacherRow.fromJson).toList();
  }

  static Future<void> renameTeacher(int id, String name) async {
    await sb.rpc('admin_rename_teacher', params: {'p_id': id, 'p_name': name});
  }

  /// Everything the admin "Today" board needs for one date (Philippine time).
  static Future<AdminDay> adminDay(DateTime day) async {
    final d = dayOf(day);
    final results = await Future.wait<dynamic>(<Future<dynamic>>[
      sb.from('teachers').select('id, name, faculty, position').eq('deleted', false).order('id').limit(500),
      sb.from('faculty').select(),
      sb.from('shifts').select(),
      sb.from('rules').select().eq('id', 1).maybeSingle(),
      sb.from('leaves').select().eq('deleted', false).lte('from_date', fDate.format(d)).gte('to_date', fDate.format(d)),
      sb
          .from('attendance_logs')
          .select('teacher_id, punched_at')
          .gte('punched_at', fStampSql.format(d))
          .lt('punched_at', fStampSql.format(d.add(const Duration(days: 1))))
          .order('punched_at')
          .limit(5000),
    ]);
    final teachers = (results[0] as List).map((e) => TeacherRow.fromJson(e as Map<String, dynamic>)).toList();
    final faculty = {for (final e in results[1] as List) (e['no'] as num).toInt(): FacultyRow.fromJson(e as Map<String, dynamic>)};
    final shifts = {for (final e in results[2] as List) (e['no'] as num).toInt(): ShiftRow.fromJson(e as Map<String, dynamic>)};
    final rules = RulesRow.fromJson(results[3] as Map<String, dynamic>?);
    final leaves = (results[4] as List).map((e) => LeaveRow.fromJson(e as Map<String, dynamic>)).toList();
    final punches = <int, List<DateTime>>{};
    for (final e in results[5] as List) {
      punches.putIfAbsent((e['teacher_id'] as num).toInt(), () => []).add(DateTime.parse(e['punched_at'] as String));
    }
    return AdminDay(d, teachers, faculty, shifts, rules, leaves, punches);
  }

  /// Saves a shift. Times are 24-hour "HH:mm" Philippine time ('' = unused).
  static Future<void> saveShift(int no, String in1, String out1, String in2, String out2, String otIn, String otOut) async {
    await sb.rpc('admin_save_shift', params: {
      'p_no': no,
      'p_in1': in1,
      'p_out1': out1,
      'p_in2': in2,
      'p_out2': out2,
      'p_ot_in': otIn,
      'p_ot_out': otOut,
    });
  }

  static Future<List<FacultyRow>> allFaculty() async {
    final r = await sb.from('faculty').select().order('no');
    return r.map(FacultyRow.fromJson).toList();
  }

  static Future<List<ShiftRow>> allShifts() async {
    final r = await sb.from('shifts').select().order('no');
    return r.map(ShiftRow.fromJson).toList();
  }

  static Future<void> addNotice(String title, String body, {int? faculty, bool pinned = false}) async {
    await sb.from('notices').insert({'title': title, 'body': body, 'faculty': faculty, 'pinned': pinned});
  }

  static Future<void> deleteNotice(int id) async {
    await sb.from('notices').delete().eq('id', id);
  }
}

/// One day for the whole school, as the admin sees it.
class AdminDay {
  final DateTime day;
  final List<TeacherRow> teachers;
  final Map<int, FacultyRow> faculty;
  final Map<int, ShiftRow> shifts;
  final RulesRow rules;
  final List<LeaveRow> leaves;
  final Map<int, List<DateTime>> punches;
  const AdminDay(this.day, this.teachers, this.faculty, this.shifts, this.rules, this.leaves, this.punches);

  bool get hasData => punches.isNotEmpty;

  MySchedule scheduleOf(TeacherRow t) => MySchedule(t.id, faculty[t.faculty], shifts, rules, leaves);

  DayView viewOf(TeacherRow t, DateTime now) => scheduleOf(t).view(day, punches[t.id] ?? const [], hasData, now);
}

String errText(Object e) {
  final m = e is PostgrestException ? e.message : e.toString();
  if (m.contains('one_approved_per_teacher')) return 'That teacher record is already linked to another approved account.';
  if (m.contains('teacher_links_user_id_key')) return 'You already have a request. Pull to refresh.';
  return m;
}

/// Always sign out through this so this phone stops receiving the user's notifications.
Future<void> signOut() async {
  await Notify.stop();
  await sb.auth.signOut();
}

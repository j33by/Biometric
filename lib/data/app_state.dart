// Central application state.
//
// Local-first: every edit lands in the on-disk database immediately, the
// device exchange files (Employee_Form.xls / Attendance_Logs.txt) are kept in
// step automatically, and the cloud (Render API -> Supabase) is a mirror that
// is flushed whenever it is reachable.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/attendance.dart';
import '../core/dates.dart';
import '../core/device_files.dart';
import '../core/models.dart';
import '../core/ph_time.dart';
import '../core/reports.dart' as reports;
import '../core/seed.dart';
import 'api_client.dart';
import 'persist.dart';

const List<String> kLogFileNames = ['Attendance_Logs.txt', 'Attendance Logs.txt'];
// The device's own file is "Employee Form.xls" (with a SPACE). It must be the
// first entry: that is the name the app writes, so the device accepts the upload.
// The underscore spelling is only recognised as a legacy name and migrated.
const List<String> kFormFileNames = ['Employee Form.xls', 'Employee_Form.xls'];

class ActivityEntry {
  final DateTime time;
  final String kind; // info | ok | warn | error
  final String text;
  ActivityEntry(this.time, this.kind, this.text);

  Map<String, dynamic> toJson() => {'t': time.toIso8601String(), 'k': kind, 'x': text};
  factory ActivityEntry.fromJson(Map<String, dynamic> j) =>
      ActivityEntry(DateTime.tryParse(j['t'] as String) ?? DateTime.now(), j['k'] as String, j['x'] as String);
}

class ImportResult {
  final String source;
  final int total;
  final int added;
  final int duplicates;
  final int bad;
  final int newTeachers;
  const ImportResult(this.source, this.total, this.added, this.duplicates, this.bad, this.newTeachers);
}

class UsbDrive {
  final String root;
  final String? logsPath;
  final String? formPath;
  const UsbDrive(this.root, this.logsPath, this.formPath);
}

enum SyncPhase { idle, syncing, error }

class AppState extends ChangeNotifier {
  // ------------------------------------------------------------ data
  final Map<int, Teacher> _teachers = {};
  final Map<int, Faculty> faculty = {};
  final Map<String, LeaveRecord> _leaves = {};
  final Map<int, Shift> shifts = {};
  Rules rules = Rules();
  final List<PunchLog> logs = [];
  final Set<String> _logKeys = {};
  final Map<String, List<PunchLog>> logsByDate = {};
  final Set<String> _dirty = {};

  // ------------------------------------------------------------ settings
  String serverUrl = '';
  String syncFolder = '';
  bool autoExport = true;
  bool autoUsb = true;
  bool writeUsb = true;
  String? token;
  AdminUser? admin;
  bool localMode = false;

  // ------------------------------------------------------------ runtime
  bool loaded = false;
  String? fatalError;
  SyncPhase syncPhase = SyncPhase.idle;
  String? syncError;
  DateTime? lastCloudSync;
  DateTime? lastExport;
  DateTime? lastImport;
  /// Set when an import contained punches later than "now" in Philippine time,
  /// i.e. the device clock is ahead (or in another zone). Shown on Device sync.
  String? clockWarning;
  List<UsbDrive> drives = const [];
  final List<ActivityEntry> activity = [];

  late Persist _persist;
  late ApiClient api;
  AttendanceBook? _book;
  int _cloudLogCursor = 0; // index into [logs] already pushed
  int _serverLogCursor = 0; // last server row id pulled
  final Map<String, String> _importedSig = {};
  final Map<String, String> _writtenSig = {};
  Timer? _saveTimer, _exportTimer, _flushTimer, _cloudTimer, _usbTimer, _folderTimer;
  StreamSubscription<FileSystemEvent>? _watchSub;
  bool _syncing = false;
  bool _usbBusy = false;

  // ============================================================ getters

  List<Teacher> get teachers {
    final l = _teachers.values.where((s) => !s.deleted).toList()..sort((a, b) => a.id.compareTo(b.id));
    return l;
  }

  Teacher? teacherById(int id) {
    final s = _teachers[id];
    return (s == null || s.deleted) ? null : s;
  }

  int get nextTeacherId {
    var m = 0;
    for (final s in _teachers.values) {
      if (s.id > m) m = s.id;
    }
    return m + 1;
  }

  String facultyName(int no) {
    final s = faculty[no];
    if (s == null || s.name.trim().isEmpty) return 'Faculty $no';
    return s.name;
  }

  /// Current Philippine wall-clock time (never the computer's own zone).
  DateTime get now => phNow();
  DateTime get today => phToday();

  List<LeaveRecord> get leaves {
    final l = _leaves.values.where((x) => !x.deleted).toList()..sort((a, b) => b.from.compareTo(a.from));
    return l;
  }

  List<LeaveRecord> leavesFor(int teacherId) => leaves.where((l) => l.teacherId == teacherId).toList();

  bool get signedIn => admin != null;
  bool get canWrite => admin?.canWrite ?? false;
  bool get cloudEnabled => token != null && api.configured && !localMode;

  AttendanceBook get book => _book ??= AttendanceBook(
        teachers: teachers,
        faculty: faculty,
        shifts: shifts,
        rules: rules,
        logsByDate: logsByDate,
        leaves: leaves,
      );

  int get pendingCloudChanges => _dirty.length + (logs.length - _cloudLogCursor);

  // ============================================================ lifecycle

  Future<void> init() async {
    try {
      final support = await getApplicationSupportDirectory();
      _persist = Persist(Directory(p.join(support.path, 'data')));
      await _persist.ensure();
      api = ApiClient();
      final db = await _persist.loadDb();
      if (db != null) {
        _loadFromJson(db);
      } else {
        await _seedFromTemplate();
      }
      for (final l in await _persist.loadLogs()) {
        _indexLog(l);
      }
      if (_cloudLogCursor > logs.length) _cloudLogCursor = logs.length;

      if (syncFolder.isEmpty) {
        final docs = await getApplicationDocumentsDirectory();
        syncFolder = p.join(docs.path, 'BiometricSync');
      }
      try {
        await Directory(syncFolder).create(recursive: true);
      } catch (_) {}

      api = ApiClient(baseUrl: serverUrl, token: token);
      loaded = true;
      notifyListeners();

      _startWatchers();
      await syncFormFile(await _formPathIn(syncFolder), quiet: true);
      await _scanFolderForLogs();
      if (cloudEnabled) {
        _startCloudTimer();
        unawaited(syncNow());
      }
    } catch (e) {
      fatalError = '$e';
      loaded = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final t in [_saveTimer, _exportTimer, _flushTimer, _cloudTimer, _usbTimer, _folderTimer]) {
      t?.cancel();
    }
    _watchSub?.cancel();
    super.dispose();
  }

  // ============================================================ persistence

  void _loadFromJson(Map<String, dynamic> j) {
    final s = (j['settings'] ?? {}) as Map<String, dynamic>;
    serverUrl = (s['serverUrl'] ?? '') as String;
    syncFolder = (s['syncFolder'] ?? '') as String;
    autoExport = (s['autoExport'] ?? true) as bool;
    autoUsb = (s['autoUsb'] ?? true) as bool;
    writeUsb = (s['writeUsb'] ?? true) as bool;
    token = s['token'] as String?;
    localMode = (s['localMode'] ?? false) as bool;
    if (s['admin'] != null) admin = AdminUser.fromJson(s['admin'] as Map<String, dynamic>);
    _cloudLogCursor = ((j['cloudLogCursor'] ?? 0) as num).toInt();
    _serverLogCursor = ((j['serverLogCursor'] ?? 0) as num).toInt();
    _importedSig.addAll(((j['importedSig'] ?? {}) as Map).map((k, v) => MapEntry(k as String, v as String)));
    _writtenSig.addAll(((j['writtenSig'] ?? {}) as Map).map((k, v) => MapEntry(k as String, v as String)));
    // Databases written by the old student version used 'student:' / 'section:' keys.
    _dirty.addAll(((j['dirty'] ?? []) as List)
        .map((e) => (e as String).replaceFirst('student:', 'teacher:').replaceFirst('section:', 'faculty:')));
    for (final e in (j['teachers'] ?? j['students'] ?? []) as List) {
      final st = Teacher.fromJson(e as Map<String, dynamic>);
      _teachers[st.id] = st;
    }
    for (final e in (j['faculty'] ?? j['sections'] ?? []) as List) {
      final sc = Faculty.fromJson(e as Map<String, dynamic>);
      faculty[sc.no] = sc;
    }
    for (final e in (j['leaves'] ?? []) as List) {
      final lv = LeaveRecord.fromJson(e as Map<String, dynamic>);
      _leaves[lv.id] = lv;
    }
    for (final e in (j['shifts'] ?? []) as List) {
      final sh = Shift.fromJson(e as Map<String, dynamic>);
      shifts[sh.no] = sh;
    }
    if (j['rules'] != null) rules = Rules.fromJson(j['rules'] as Map<String, dynamic>);
    for (final e in (j['activity'] ?? []) as List) {
      activity.add(ActivityEntry.fromJson(e as Map<String, dynamic>));
    }
    _ensureDefaults();
  }

  Map<String, dynamic> _toJson() => {
        'settings': {
          'serverUrl': serverUrl,
          'syncFolder': syncFolder,
          'autoExport': autoExport,
          'autoUsb': autoUsb,
          'writeUsb': writeUsb,
          'token': token,
          'localMode': localMode,
          'admin': admin?.toJson(),
        },
        'cloudLogCursor': _cloudLogCursor,
        'serverLogCursor': _serverLogCursor,
        'importedSig': _importedSig,
        'writtenSig': _writtenSig,
        'dirty': _dirty.toList(),
        'teachers': _teachers.values.map((e) => e.toJson()).toList(),
        'faculty': faculty.values.map((e) => e.toJson()).toList(),
        'leaves': _leaves.values.map((e) => e.toJson()).toList(),
        'shifts': shifts.values.map((e) => e.toJson()).toList(),
        'rules': rules.toJson(),
        'activity': activity.reversed.take(60).toList().reversed.map((e) => e.toJson()).toList(),
      };

  void _saveSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      _persist.saveDb(_toJson()).catchError((Object e) {
        _log('error', 'Could not save local database: $e');
      });
    });
  }

  void _ensureDefaults() {
    for (var i = 1; i <= 16; i++) {
      faculty.putIfAbsent(i, () => Faculty(no: i, name: i == 1 ? 'Faculty 1' : ''));
    }
    for (var i = 1; i <= 10; i++) {
      shifts.putIfAbsent(i, () => Shift(no: i));
    }
  }

  /// Puts the Grade 12 ABM class program (teachers, faculty slots, shifts) into the app.
  /// [stamp] decides who wins against what is already in the cloud: first-run seeding
  /// uses an old date (anything already saved wins), the button uses "now".
  void _applyStarter(DateTime stamp) {
    final s = cnhsG12AbmStarter(stamp);
    for (final x in s.teachers) {
      _teachers[x.id] = x;
      _dirty.add('teacher:${x.id}');
    }
    for (final x in s.faculty) {
      faculty[x.no] = x;
      _dirty.add('faculty:${x.no}');
    }
    for (final x in s.shifts) {
      shifts[x.no] = x;
      _dirty.add('shift:${x.no}');
    }
  }

  /// "Load starter schedule" button: overwrites teachers 4-8, faculty slots 1-16 and shifts 1-10.
  void loadStarterSchedule() {
    _applyStarter(DateTime.now());
    if (rules.company.trim().isEmpty || rules.company.trim().toLowerCase() == 'cnhs') {
      rules = rules.copy()
        ..company = 'Calape National High School'
        ..updatedAt = DateTime.now();
      _dirty.add('rules');
    }
    _log('ok', 'Loaded the Grade 12 ABM class program: teachers 4-8, 7 shifts, 6 faculty slots.');
    _changed();
  }

  Future<void> _seedFromTemplate() async {
    try {
      final data = await rootBundle.load('assets/templates/Employee_Form.xls');
      final form = readDeviceForm(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      // The bundled template is the school's own device file. Keep everyone already on
      // the device (so nothing is lost on upload), then lay the corrected class program
      // over it (shifts, faculty slots and teachers 4-8).
      for (final s in form.teachers) {
        if (s.name.trim().isEmpty) continue;
        s.updatedAt = DateTime(2026, 1, 1);
        _teachers[s.id] = s;
        _dirty.add('teacher:${s.id}');
      }
      if (form.rulesFound) rules = form.rules;
    } catch (_) {
      // fall through to defaults
    }
    if (rules.company.trim().isEmpty || rules.company.trim().toLowerCase() == 'cnhs') {
      rules.company = 'Calape National High School';
    }
    rules.updatedAt = DateTime(2026, 1, 1);
    _applyStarter(DateTime(2026, 1, 1));
    _ensureDefaults();
    _log('info', 'First run: loaded the Grade 12 ABM class program (${_teachers.length} teachers, 6 shifts).');
    _saveSoon();
  }

  void _log(String kind, String text) {
    activity.add(ActivityEntry(DateTime.now(), kind, text));
    if (activity.length > 200) activity.removeRange(0, activity.length - 200);
    notifyListeners();
  }

  void _changed({bool exportForm = true, bool cloud = true}) {
    _book = null;
    _saveSoon();
    if (exportForm) _scheduleExport();
    if (cloud) _scheduleFlush();
    notifyListeners();
  }

  // ============================================================ editing

  Teacher addTeacher(
      {required String name,
      required int facultyNo,
      int authority = 0,
      String teacherNo = '',
      String position = '',
      String contact = '',
      String notes = ''}) {
    final s = Teacher(
        id: nextTeacherId,
        name: name.trim(),
        faculty: facultyNo,
        authority: authority,
        teacherNo: teacherNo,
        position: position,
        contact: contact,
        notes: notes);
    _teachers[s.id] = s;
    _dirty.add('teacher:${s.id}');
    _log('ok', 'Added teacher ${s.id} · ${s.name}');
    _changed();
    return s;
  }

  /// Creates or replaces a teacher with an explicit device ID.
  String? saveTeacher(Teacher s, {required bool isNew}) {
    if (isNew && _teachers[s.id] != null && !_teachers[s.id]!.deleted) {
      return 'ID ${s.id} is already used by ${_teachers[s.id]!.name}';
    }
    s.updatedAt = DateTime.now();
    s.deleted = false;
    _teachers[s.id] = s;
    _dirty.add('teacher:${s.id}');
    _log('ok', '${isNew ? 'Added' : 'Updated'} teacher ${s.id} · ${s.name}');
    _changed();
    return null;
  }

  void deleteTeacher(int id) {
    final s = _teachers[id];
    if (s == null) return;
    s.deleted = true;
    s.updatedAt = DateTime.now();
    _dirty.add('teacher:$id');
    _log('warn', 'Removed teacher $id · ${s.name}');
    _changed();
    if (!cloudEnabled) _purgeTombstones();
  }

  /// True if another teacher already has this Teacher ID (the DepEd / employee number).
  Teacher? teacherWithNo(String teacherNo, {int? exceptId}) {
    final n = teacherNo.trim().toLowerCase();
    if (n.isEmpty) return null;
    for (final t in teachers) {
      if (t.id != exceptId && t.teacherNo.trim().toLowerCase() == n) return t;
    }
    return null;
  }

  // ------------------------------------------------------------ leaves

  String newLeaveId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${(DateTime.now().millisecond * 7919 % 46656).toRadixString(36)}';

  void saveLeave(LeaveRecord l) {
    l.updatedAt = DateTime.now();
    l.deleted = false;
    _leaves[l.id] = l;
    _dirty.add('leave:${l.id}');
    final who = teacherById(l.teacherId)?.name ?? 'ID ${l.teacherId}';
    _log('ok', 'Leave saved for $who · ${l.type} · ${fmtDayMonth(l.from)}${l.days > 1 ? ' – ${fmtDayMonth(l.to)}' : ''}');
    _changed(exportForm: false);
  }

  void deleteLeave(String id) {
    final l = _leaves[id];
    if (l == null) return;
    l.deleted = true;
    l.updatedAt = DateTime.now();
    _dirty.add('leave:$id');
    _log('warn', 'Leave removed (${l.type}, ID ${l.teacherId})');
    _changed(exportForm: false);
    if (!cloudEnabled) _leaves.remove(id);
  }

  void saveFaculty(Faculty s) {
    s.updatedAt = DateTime.now();
    faculty[s.no] = s;
    _dirty.add('faculty:${s.no}');
    _log('ok', 'Saved faculty ${s.no} · ${s.name}');
    _changed();
  }

  void saveShift(Shift s) {
    s.updatedAt = DateTime.now();
    shifts[s.no] = s;
    _dirty.add('shift:${s.no}');
    _log('ok', 'Saved shift ${s.no}');
    _changed();
  }

  /// Device clock correction in minutes (0 = the device already shows Philippine time).
  /// Applies to punches imported from now on - see importLogsFromBytes.
  void setClockOffset(int minutes) {
    final r = rules.copy()..clockOffsetMin = minutes;
    saveRules(r);
    clockWarning = null;
  }

  void saveRules(Rules r) {
    r.updatedAt = DateTime.now();
    rules = r;
    _dirty.add('rules');
    _log('ok', 'Saved attendance rules');
    _changed();
  }

  void _purgeTombstones() {
    _teachers.removeWhere((_, s) => s.deleted && !_dirty.contains('teacher:${s.id}'));
    _leaves.removeWhere((_, l) => l.deleted && !_dirty.contains('leave:${l.id}'));
  }

  // ============================================================ logs

  bool _indexLog(PunchLog l) {
    if (!_logKeys.add(l.key)) return false;
    logs.add(l);
    logsByDate.putIfAbsent(fmtDate(l.time), () => []).add(l);
    return true;
  }

  Future<ImportResult> importLogsFromBytes(Uint8List bytes, String source) async {
    final parsed = parseAttendanceLogs(decodeLogBytes(bytes));
    final added = <PunchLog>[];
    var dup = 0;
    var newTeachers = 0;
    // If the device clock is off, the admin set a correction (Device sync > Device clock).
    // It is applied here, once, so every stored punch (and the cloud copy) is Philippine time.
    final offset = Duration(minutes: rules.clockOffsetMin);
    final phNowTime = phNow();
    DateTime? latest;
    for (final raw in parsed.logs) {
      final l = offset == Duration.zero
          ? raw
          : PunchLog(teacherId: raw.teacherId, name: raw.name, dept: raw.dept, time: raw.time.add(offset), deviceId: raw.deviceId);
      if (latest == null || l.time.isAfter(latest)) latest = l.time;
      if (_indexLog(l)) {
        added.add(l);
        final existing = _teachers[l.teacherId];
        if (existing == null) {
          // Match the device's "Dept." text to a faculty slot (its subject name). If none
          // matches, use the first empty slot (no duty) so nobody is marked late or absent
          // against someone else's schedule; the admin then picks the right faculty.
          var sec = 0;
          for (final s in faculty.values) {
            if (s.name.trim().isNotEmpty && s.name.trim().toLowerCase() == l.dept.toLowerCase()) sec = s.no;
          }
          if (sec == 0) {
            final empty = faculty.values.where((s) => s.name.trim().isEmpty).toList()..sort((a, b) => a.no.compareTo(b.no));
            sec = empty.isEmpty ? 1 : empty.first.no;
          }
          _teachers[l.teacherId] = Teacher(
              id: l.teacherId, name: l.name, faculty: sec, notes: 'Added automatically from a device log - set the faculty / subject');
          _dirty.add('teacher:${l.teacherId}');
          newTeachers++;
        } else if (existing.deleted) {
          existing.deleted = false;
          existing.updatedAt = DateTime.now();
          _dirty.add('teacher:${l.teacherId}');
          newTeachers++;
        }
      } else {
        dup++;
      }
    }
    await _persist.appendLogs(added);
    lastImport = DateTime.now();
    // A punch from the future can only mean the device clock is ahead of Philippine time.
    if (latest != null && latest.isAfter(phNowTime.add(const Duration(minutes: 10)))) {
      final ahead = latest.difference(phNowTime);
      clockWarning = 'The newest punch (${fmtDateTime(latest)}) is ${fmtDuration(ahead.inMinutes)} ahead of Philippine time '
          '(${fmtDateTime(phNowTime)}). The device clock looks wrong. Check it under Device sync > Device clock.';
      _log('warn', clockWarning!);
    } else if (parsed.logs.isNotEmpty) {
      clockWarning = null;
    }
    final res = ImportResult(source, parsed.logs.length, added.length, dup, parsed.badLines, newTeachers);
    final extra = [
      if (dup > 0) '$dup already known',
      if (newTeachers > 0) '$newTeachers new teacher${newTeachers == 1 ? '' : 's'}',
      if (parsed.badLines > 0) '${parsed.badLines} unreadable line${parsed.badLines == 1 ? '' : 's'}',
    ];
    _log(added.isEmpty ? 'info' : 'ok',
        'Imported ${added.length} new punch${added.length == 1 ? '' : 'es'} from $source${extra.isEmpty ? '' : ' (${extra.join(', ')})'}');
    _changed(exportForm: newTeachers > 0);
    return res;
  }

  Future<ImportResult?> importLogsFromPath(String path, {bool force = false}) async {
    String? sig;
    try {
      final f = File(path);
      final st = await f.stat();
      sig = '${st.size}:${st.modified.millisecondsSinceEpoch}';
      if (!force && _importedSig[path] == sig) return null;
      final bytes = await f.readAsBytes();
      final res = await importLogsFromBytes(bytes, p.basename(path));
      _importedSig[path] = sig;
      _saveSoon();
      return res;
    } catch (e) {
      // remember the failing version so we do not retry it every few seconds
      if (sig != null) _importedSig[path] = sig;
      _log('error', 'Could not import $path: $e');
      return null;
    }
  }

  // ============================================================ device form

  Future<Uint8List> _assetTemplate() async {
    final data = await rootBundle.load('assets/templates/Employee_Form.xls');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  Future<String> _sigOf(File f) async {
    final st = await f.stat();
    return '${st.size}:${st.modified.millisecondsSinceEpoch}';
  }

  /// Merges a device Employee Form into the app. The file wins on conflicts.
  Future<int> importFormFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final form = readDeviceForm(bytes);
    var changed = 0;
    for (final s in form.teachers) {
      final cur = _teachers[s.id];
      if (cur == null || cur.deleted) {
        _teachers[s.id] = s..updatedAt = DateTime.now();
        _dirty.add('teacher:${s.id}');
        changed++;
      } else if (cur.name != s.name || cur.faculty != s.faculty || cur.authority != s.authority) {
        cur
          ..name = s.name
          ..faculty = s.faculty
          ..authority = s.authority
          ..updatedAt = DateTime.now();
        if (s.schedule != null) cur.schedule = s.schedule;
        _dirty.add('teacher:${s.id}');
        changed++;
      }
    }
    if (form.rulesFound) {
      for (final sec in form.faculty) {
        final cur = faculty[sec.no];
        if (cur == null || cur.name != sec.name || cur.week.join() != sec.week.join()) {
          faculty[sec.no] = sec..updatedAt = DateTime.now();
          _dirty.add('faculty:${sec.no}');
          changed++;
        }
      }
      for (final sh in form.shifts) {
        final cur = shifts[sh.no];
        if (cur == null ||
            cur.in1 != sh.in1 ||
            cur.out1 != sh.out1 ||
            cur.in2 != sh.in2 ||
            cur.out2 != sh.out2 ||
            cur.otIn != sh.otIn ||
            cur.otOut != sh.otOut) {
          shifts[sh.no] = sh..updatedAt = DateTime.now();
          _dirty.add('shift:${sh.no}');
          changed++;
        }
      }
      final r = form.rules;
      if (r.company != rules.company ||
          r.lateAllow != rules.lateAllow ||
          r.earlyAllow != rules.earlyAllow ||
          r.repeatMin != rules.repeatMin ||
          r.scheduleMode != rules.scheduleMode) {
        r.clockOffsetMin = rules.clockOffsetMin; // the Excel file has no cell for it - keep ours
        rules = r..updatedAt = DateTime.now();
        _dirty.add('rules');
        changed++;
      }
    }
    if (changed > 0) {
      _log('ok', 'Merged $changed change${changed == 1 ? '' : 's'} from ${p.basename(path)}');
      _changed(exportForm: false);
    }
    return changed;
  }

  /// Writes the Employee Form to [path], using the existing file there (the
  /// device's own) as the template.  If that file was edited outside the app
  /// since we last wrote it, its changes are merged in first.
  Future<bool> exportFormTo(String path, {bool quiet = false}) async {
    try {
      final f = File(path);
      Uint8List template;
      if (await f.exists()) {
        template = await f.readAsBytes();
        try {
          readDeviceForm(template);
        } catch (_) {
          template = await _assetTemplate();
        }
      } else {
        template = await _assetTemplate();
      }
      final out = writeDeviceForm(
        template,
        teachers: teachers,
        faculty: faculty.values.toList(),
        shifts: shifts.values.toList(),
        rules: rules,
      );
      await Persist.writeAtomic(f, out);
      _writtenSig[path] = await _sigOf(f);
      lastExport = DateTime.now();
      if (!quiet) _log('ok', 'Wrote ${p.basename(path)} (${teachers.length} teachers) to ${p.dirname(path)}');
      _saveSoon();
      notifyListeners();
      return true;
    } catch (e) {
      _log('error', 'Could not write $path: $e');
      return false;
    }
  }

  /// Merge external edits (if any) and then write the app's state back.
  Future<void> syncFormFile(String path, {bool quiet = false}) async {
    try {
      final f = File(path);
      if (await f.exists()) {
        final sig = await _sigOf(f);
        if (_writtenSig[path] != sig) {
          try {
            await importFormFile(path);
          } catch (e) {
            _log('warn', 'Existing ${p.basename(path)} could not be read ($e); it will be replaced.');
          }
        }
      }
    } catch (_) {}
    await exportFormTo(path, quiet: quiet);
  }

  void _scheduleExport() {
    if (!autoExport) return;
    _exportTimer?.cancel();
    _exportTimer = Timer(const Duration(milliseconds: 1200), () async {
      await exportFormTo(await _formPathIn(syncFolder));
      if (writeUsb) {
        for (final d in drives) {
          if (d.formPath != null) await exportFormTo(d.formPath!, quiet: true);
        }
      }
    });
  }

  Future<void> exportNow() async {
    await exportFormTo(await _formPathIn(syncFolder));
    if (writeUsb) {
      for (final d in drives) {
        final target = d.formPath ?? p.join(d.root, kFormFileNames.first);
        await exportFormTo(target);
      }
    }
  }

  // ============================================================ watching

  /// Path of the device form inside [dir]. Always "Employee Form.xls" (space).
  /// A legacy "Employee_Form.xls" written by older versions is renamed to it.
  Future<String> _formPathIn(String dir) async {
    final wanted = p.join(dir, kFormFileNames.first);
    if (await File(wanted).exists()) return wanted;
    final legacy = p.join(dir, kFormFileNames[1]);
    try {
      if (await File(legacy).exists()) {
        await File(legacy).rename(wanted);
        _log('info', 'Renamed ${kFormFileNames[1]} to ${kFormFileNames.first} so the device accepts it.');
      }
    } catch (_) {
      if (await File(legacy).exists()) return legacy;
    }
    return wanted;
  }

  Future<String?> _firstExisting(String dir, List<String> names) async {
    for (final n in names) {
      final path = p.join(dir, n);
      if (await File(path).exists()) return path;
    }
    return null;
  }

  Future<void> _scanFolderForLogs() async {
    final path = await _firstExisting(syncFolder, kLogFileNames);
    if (path != null) await importLogsFromPath(path);
  }

  void _startWatchers() {
    _watchSub?.cancel();
    try {
      _watchSub = Directory(syncFolder).watch().listen((event) {
        final name = p.basename(event.path).toLowerCase();
        final isLogs = kLogFileNames.any((n) => n.toLowerCase() == name);
        final isForm = kFormFileNames.any((n) => n.toLowerCase() == name);
        if (!isLogs && !isForm) return;
        _folderTimer?.cancel();
        _folderTimer = Timer(const Duration(milliseconds: 900), () async {
          if (isLogs) await _scanFolderForLogs();
          if (isForm) {
            final path = await _firstExisting(syncFolder, kFormFileNames);
            if (path != null && _writtenSig[path] != await _sigOf(File(path))) {
              await syncFormFile(path);
            }
          }
        });
      }, onError: (Object e) {
        _log('warn', 'Folder watching stopped: $e');
      });
    } catch (e) {
      _log('warn', 'Cannot watch $syncFolder: $e');
    }
    _usbTimer?.cancel();
    if (Platform.isWindows) {
      _usbTimer = Timer.periodic(const Duration(seconds: 4), (_) => _pollUsb());
      unawaited(_pollUsb());
    }
  }

  Future<void> setSyncFolder(String path) async {
    syncFolder = path;
    try {
      await Directory(path).create(recursive: true);
    } catch (_) {}
    _startWatchers();
    _log('info', 'Sync folder set to $path');
    _saveSoon();
    await syncFormFile(await _formPathIn(path));
    await _scanFolderForLogs();
    notifyListeners();
  }

  Future<void> _pollUsb() async {
    if (_usbBusy) return;
    _usbBusy = true;
    try {
      final letters = 'DEFGHIJKLMNOPQRSTUVWXYZ'.split('');
      final found = <UsbDrive>[];
      await Future.wait(letters.map((l) async {
        final root = '$l:\\';
        final logs = await _firstExisting(root, kLogFileNames);
        final form = await _firstExisting(root, kFormFileNames);
        if (logs != null || form != null) found.add(UsbDrive(root, logs, form));
      }));
      found.sort((a, b) => a.root.compareTo(b.root));
      final before = drives.map((d) => d.root).toSet();
      final changed = before.length != found.length || found.any((d) => !before.contains(d.root));
      drives = found;
      if (changed) notifyListeners();
      if (!autoUsb) return;
      for (final d in found) {
        final isNew = !before.contains(d.root);
        var sigChanged = false;
        if (d.logsPath != null) {
          final sig = await _sigOf(File(d.logsPath!));
          sigChanged = _importedSig[d.logsPath!] != sig;
        }
        if (isNew) _log('info', 'Device USB detected on ${d.root}');
        if (isNew || sigChanged) {
          if (d.logsPath != null) await importLogsFromPath(d.logsPath!);
          if (writeUsb) {
            final target = d.formPath ?? p.join(d.root, kFormFileNames.first);
            await syncFormFile(target);
            final f = await _firstExisting(d.root, kFormFileNames);
            drives = drives
                .map((x) => x.root == d.root ? UsbDrive(x.root, x.logsPath, f ?? target) : x)
                .toList();
          }
        } else if (d.formPath != null && writeUsb) {
          // someone edited the form on the stick in Excel: pull the edits in
          final sig = await _sigOf(File(d.formPath!));
          if (_writtenSig[d.formPath!] != sig) await syncFormFile(d.formPath!);
        }
      }
    } catch (_) {
      // drive vanished mid-scan; ignore
    } finally {
      _usbBusy = false;
    }
  }

  Future<void> rescanUsb() => _pollUsb();

  // ============================================================ cloud

  Future<void> signIn(String email, String password) async {
    api = ApiClient(baseUrl: serverUrl, token: null);
    final a = await api.login(email, password);
    admin = a;
    token = api.token;
    localMode = false;
    _log('ok', 'Signed in as ${a.email}');
    _saveSoon();
    _startCloudTimer();
    notifyListeners();
    unawaited(syncNow());
  }

  void useLocalMode() {
    localMode = true;
    token = null;
    admin = const AdminUser(id: 'local', email: 'local', name: 'Local admin', role: 'superadmin');
    _cloudTimer?.cancel();
    _log('info', 'Working offline (local mode)');
    _saveSoon();
    notifyListeners();
  }

  void signOut() {
    admin = null;
    token = null;
    localMode = false;
    api.token = null;
    _cloudTimer?.cancel();
    _saveSoon();
    notifyListeners();
  }

  void updateSettings({bool? autoExport, bool? autoUsb, bool? writeUsb}) {
    if (autoExport != null) this.autoExport = autoExport;
    if (autoUsb != null) this.autoUsb = autoUsb;
    if (writeUsb != null) this.writeUsb = writeUsb;
    _saveSoon();
    notifyListeners();
    if (autoExport == true) unawaited(exportNow());
  }

  Future<void> setServerUrl(String url) async {
    serverUrl = url.trim();
    api.baseUrl = serverUrl;
    _saveSoon();
    notifyListeners();
  }

  void _startCloudTimer() {
    _cloudTimer?.cancel();
    _cloudTimer = Timer.periodic(const Duration(seconds: 45), (_) => syncNow());
  }

  void _scheduleFlush() {
    if (!cloudEnabled) return;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(seconds: 3), () => syncNow());
  }

  Future<void> syncNow() async {
    if (_syncing || !cloudEnabled) return;
    _syncing = true;
    syncPhase = SyncPhase.syncing;
    notifyListeners();
    try {
      api.token = token;
      if (canWrite) {
        await _flushDirty();
        await _flushLogs();
      }
      await _pullSnapshot();
      await _pullLogs();
      lastCloudSync = DateTime.now();
      syncError = null;
      syncPhase = SyncPhase.idle;
    } on ApiException catch (e) {
      syncError = e.message;
      syncPhase = SyncPhase.error;
      if (e.isAuth) {
        _log('warn', 'Cloud session expired – please sign in again.');
        token = null;
        admin = null;
        _cloudTimer?.cancel();
        _saveSoon();
      }
    } catch (e) {
      syncError = '$e';
      syncPhase = SyncPhase.error;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> _flushDirty() async {
    if (_dirty.isEmpty) return;
    final keys = _dirty.toList();
    final st = <Teacher>[];
    final sc = <Faculty>[];
    final sh = <Shift>[];
    final lv = <LeaveRecord>[];
    Rules? ru;
    for (final k in keys) {
      if (k.startsWith('teacher:')) {
        final s = _teachers[int.parse(k.substring(8))];
        if (s != null) st.add(s);
      } else if (k.startsWith('faculty:')) {
        final s = faculty[int.parse(k.substring(8))];
        if (s != null) sc.add(s);
      } else if (k.startsWith('shift:')) {
        final s = shifts[int.parse(k.substring(6))];
        if (s != null) sh.add(s);
      } else if (k.startsWith('leave:')) {
        final s = _leaves[k.substring(6)];
        if (s != null) lv.add(s);
      } else if (k == 'rules') {
        ru = rules;
      }
    }
    await api.push(teachers: st, faculty: sc, shifts: sh, leaves: lv, rules: ru);
    _dirty.removeAll(keys);
    _purgeTombstones();
    _saveSoon();
  }

  Future<void> _flushLogs() async {
    while (_cloudLogCursor < logs.length) {
      final end = (_cloudLogCursor + 1000) > logs.length ? logs.length : _cloudLogCursor + 1000;
      final batch = logs.sublist(_cloudLogCursor, end);
      await api.pushLogs(batch);
      _cloudLogCursor = end;
      _saveSoon();
    }
  }

  Future<void> _pullSnapshot() async {
    final snap = await api.snapshot();
    var changed = false;
    for (final cs in snap.teachers) {
      if (_dirty.contains('teacher:${cs.id}')) continue;
      final cur = _teachers[cs.id];
      if (cur == null || cs.updatedAt.isAfter(cur.updatedAt)) {
        if (cs.deleted) {
          if (cur != null) {
            _teachers.remove(cs.id);
            changed = true;
          }
        } else {
          _teachers[cs.id] = cs;
          changed = true;
        }
      }
    }
    for (final cs in snap.faculty) {
      if (_dirty.contains('faculty:${cs.no}')) continue;
      final cur = faculty[cs.no];
      if (cur == null || cs.updatedAt.isAfter(cur.updatedAt)) {
        faculty[cs.no] = cs;
        changed = true;
      }
    }
    for (final cs in snap.shifts) {
      if (_dirty.contains('shift:${cs.no}')) continue;
      final cur = shifts[cs.no];
      if (cur == null || cs.updatedAt.isAfter(cur.updatedAt)) {
        shifts[cs.no] = cs;
        changed = true;
      }
    }
    for (final cl in snap.leaves) {
      if (_dirty.contains('leave:${cl.id}')) continue;
      final cur = _leaves[cl.id];
      if (cur == null || cl.updatedAt.isAfter(cur.updatedAt)) {
        if (cl.deleted) {
          if (cur != null) {
            _leaves.remove(cl.id);
            changed = true;
          }
        } else {
          _leaves[cl.id] = cl;
          changed = true;
        }
      }
    }
    final r = snap.rules;
    if (r != null && !_dirty.contains('rules') && r.updatedAt.isAfter(rules.updatedAt)) {
      rules = r;
      changed = true;
    }
    if (changed) {
      _ensureDefaults();
      _changed(cloud: false);
    }
  }

  Future<void> _pullLogs() async {
    var more = true;
    var guard = 0;
    while (more && guard++ < 200) {
      final page = await api.pullLogs(_serverLogCursor);
      final added = <PunchLog>[];
      for (final l in page.logs) {
        if (_indexLog(l)) added.add(l);
      }
      await _persist.appendLogs(added);
      _serverLogCursor = page.cursor;
      more = page.hasMore && page.logs.isNotEmpty;
      if (added.isNotEmpty) {
        _book = null;
        notifyListeners();
      }
    }
    // everything we hold is now known to the server (pushed or pulled)
    _cloudLogCursor = logs.length;
    _saveSoon();
  }

  // ============================================================ exports

  /// CSV of one day's attendance (opens fine in Excel).
  String dayCsv(DateTime day) => reports.dayCsv(book, day, facultyName);

  /// One row per teacher with the month's totals.
  String monthCsv(DateTime month) => reports.monthCsv(book, month, facultyName);

  /// Daily Time Record of one teacher for a month.
  String dtrCsv(Teacher t, DateTime month) =>
      reports.dtrCsv(book, t, month, facultyName(t.faculty), rules.company);

  Future<String> writeText(String path, String text) async {
    await File(path).writeAsBytes(utf8.encode(text));
    return path;
  }
}

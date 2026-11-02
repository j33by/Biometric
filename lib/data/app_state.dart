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
import 'api_client.dart';
import 'persist.dart';

const List<String> kLogFileNames = ['Attendance_Logs.txt', 'Attendance Logs.txt'];
const List<String> kFormFileNames = ['Employee_Form.xls', 'Employee Form.xls'];

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
  final int newStudents;
  const ImportResult(this.source, this.total, this.added, this.duplicates, this.bad, this.newStudents);
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
  final Map<int, Student> _students = {};
  final Map<int, Section> sections = {};
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

  List<Student> get students {
    final l = _students.values.where((s) => !s.deleted).toList()..sort((a, b) => a.id.compareTo(b.id));
    return l;
  }

  Student? studentById(int id) {
    final s = _students[id];
    return (s == null || s.deleted) ? null : s;
  }

  int get nextStudentId {
    var m = 0;
    for (final s in _students.values) {
      if (s.id > m) m = s.id;
    }
    return m + 1;
  }

  String sectionName(int no) {
    final s = sections[no];
    if (s == null || s.name.trim().isEmpty) return 'Section $no';
    return s.name;
  }

  bool get signedIn => admin != null;
  bool get canWrite => admin?.canWrite ?? false;
  bool get cloudEnabled => token != null && api.configured && !localMode;

  AttendanceBook get book => _book ??= AttendanceBook(
        students: students,
        sections: sections,
        shifts: shifts,
        rules: rules,
        logsByDate: logsByDate,
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
      await syncFormFile(p.join(syncFolder, kFormFileNames.first), quiet: true);
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
    _dirty.addAll(((j['dirty'] ?? []) as List).map((e) => e as String));
    for (final e in (j['students'] ?? []) as List) {
      final st = Student.fromJson(e as Map<String, dynamic>);
      _students[st.id] = st;
    }
    for (final e in (j['sections'] ?? []) as List) {
      final sc = Section.fromJson(e as Map<String, dynamic>);
      sections[sc.no] = sc;
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
        'students': _students.values.map((e) => e.toJson()).toList(),
        'sections': sections.values.map((e) => e.toJson()).toList(),
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
      sections.putIfAbsent(i, () => Section(no: i, name: i == 1 ? 'Section 1' : ''));
    }
    for (var i = 1; i <= 10; i++) {
      shifts.putIfAbsent(i, () => i == 1 ? Shift(no: 1, in1: '08:00', out1: '17:00') : Shift(no: i));
    }
  }

  Future<void> _seedFromTemplate() async {
    try {
      final data = await rootBundle.load('assets/templates/Employee_Form.xls');
      final form = readDeviceForm(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      for (final s in form.students) {
        _students[s.id] = s;
      }
      for (final s in form.sections) {
        sections[s.no] = s;
      }
      for (final s in form.shifts) {
        shifts[s.no] = s;
      }
      if (form.rulesFound) rules = form.rules;
    } catch (_) {
      // fall through to defaults
    }
    _ensureDefaults();
    _log('info', 'First run: loaded the starter Employee Form (${_students.length} students).');
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

  Student addStudent({required String name, required int section, int authority = 0, String lrn = '', String contact = '', String notes = ''}) {
    final s = Student(
        id: nextStudentId, name: name.trim(), section: section, authority: authority, lrn: lrn, contact: contact, notes: notes);
    _students[s.id] = s;
    _dirty.add('student:${s.id}');
    _log('ok', 'Added student ${s.id} · ${s.name}');
    _changed();
    return s;
  }

  /// Creates or replaces a student with an explicit device ID.
  String? saveStudent(Student s, {required bool isNew}) {
    if (isNew && _students[s.id] != null && !_students[s.id]!.deleted) {
      return 'ID ${s.id} is already used by ${_students[s.id]!.name}';
    }
    s.updatedAt = DateTime.now();
    s.deleted = false;
    _students[s.id] = s;
    _dirty.add('student:${s.id}');
    _log('ok', '${isNew ? 'Added' : 'Updated'} student ${s.id} · ${s.name}');
    _changed();
    return null;
  }

  void deleteStudent(int id) {
    final s = _students[id];
    if (s == null) return;
    s.deleted = true;
    s.updatedAt = DateTime.now();
    _dirty.add('student:$id');
    _log('warn', 'Removed student $id · ${s.name}');
    _changed();
    if (!cloudEnabled) _purgeTombstones();
  }

  void saveSection(Section s) {
    s.updatedAt = DateTime.now();
    sections[s.no] = s;
    _dirty.add('section:${s.no}');
    _log('ok', 'Saved section ${s.no} · ${s.name}');
    _changed();
  }

  void saveShift(Shift s) {
    s.updatedAt = DateTime.now();
    shifts[s.no] = s;
    _dirty.add('shift:${s.no}');
    _log('ok', 'Saved shift ${s.no}');
    _changed();
  }

  void saveRules(Rules r) {
    r.updatedAt = DateTime.now();
    rules = r;
    _dirty.add('rules');
    _log('ok', 'Saved attendance rules');
    _changed();
  }

  void _purgeTombstones() {
    _students.removeWhere((_, s) => s.deleted && !_dirty.contains('student:${s.id}'));
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
    var newStudents = 0;
    for (final l in parsed.logs) {
      if (_indexLog(l)) {
        added.add(l);
        final existing = _students[l.studentId];
        if (existing == null) {
          var sec = 1;
          for (final s in sections.values) {
            if (s.name.trim().isNotEmpty && s.name.trim().toLowerCase() == l.dept.toLowerCase()) sec = s.no;
          }
          _students[l.studentId] = Student(
              id: l.studentId, name: l.name, section: sec, notes: 'Added automatically from a device log');
          _dirty.add('student:${l.studentId}');
          newStudents++;
        } else if (existing.deleted) {
          existing.deleted = false;
          existing.updatedAt = DateTime.now();
          _dirty.add('student:${l.studentId}');
          newStudents++;
        }
      } else {
        dup++;
      }
    }
    await _persist.appendLogs(added);
    lastImport = DateTime.now();
    final res = ImportResult(source, parsed.logs.length, added.length, dup, parsed.badLines, newStudents);
    final extra = [
      if (dup > 0) '$dup already known',
      if (newStudents > 0) '$newStudents new student${newStudents == 1 ? '' : 's'}',
      if (parsed.badLines > 0) '${parsed.badLines} unreadable line${parsed.badLines == 1 ? '' : 's'}',
    ];
    _log(added.isEmpty ? 'info' : 'ok',
        'Imported ${added.length} new punch${added.length == 1 ? '' : 'es'} from $source${extra.isEmpty ? '' : ' (${extra.join(', ')})'}');
    _changed(exportForm: newStudents > 0);
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
    for (final s in form.students) {
      final cur = _students[s.id];
      if (cur == null || cur.deleted) {
        _students[s.id] = s..updatedAt = DateTime.now();
        _dirty.add('student:${s.id}');
        changed++;
      } else if (cur.name != s.name || cur.section != s.section || cur.authority != s.authority) {
        cur
          ..name = s.name
          ..section = s.section
          ..authority = s.authority
          ..updatedAt = DateTime.now();
        if (s.schedule != null) cur.schedule = s.schedule;
        _dirty.add('student:${s.id}');
        changed++;
      }
    }
    if (form.rulesFound) {
      for (final sec in form.sections) {
        final cur = sections[sec.no];
        if (cur == null || cur.name != sec.name || cur.week.join() != sec.week.join()) {
          sections[sec.no] = sec..updatedAt = DateTime.now();
          _dirty.add('section:${sec.no}');
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
        students: students,
        sections: sections.values.toList(),
        shifts: shifts.values.toList(),
        rules: rules,
      );
      await Persist.writeAtomic(f, out);
      _writtenSig[path] = await _sigOf(f);
      lastExport = DateTime.now();
      if (!quiet) _log('ok', 'Wrote ${p.basename(path)} (${students.length} students) to ${p.dirname(path)}');
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
      await exportFormTo(p.join(syncFolder, kFormFileNames.first));
      if (writeUsb) {
        for (final d in drives) {
          if (d.formPath != null) await exportFormTo(d.formPath!, quiet: true);
        }
      }
    });
  }

  Future<void> exportNow() async {
    await exportFormTo(p.join(syncFolder, kFormFileNames.first));
    if (writeUsb) {
      for (final d in drives) {
        final target = d.formPath ?? p.join(d.root, kFormFileNames.first);
        await exportFormTo(target);
      }
    }
  }

  // ============================================================ watching

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
    await syncFormFile(p.join(path, kFormFileNames.first));
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
    final st = <Student>[];
    final sc = <Section>[];
    final sh = <Shift>[];
    Rules? ru;
    for (final k in keys) {
      if (k.startsWith('student:')) {
        final s = _students[int.parse(k.substring(8))];
        if (s != null) st.add(s);
      } else if (k.startsWith('section:')) {
        final s = sections[int.parse(k.substring(8))];
        if (s != null) sc.add(s);
      } else if (k.startsWith('shift:')) {
        final s = shifts[int.parse(k.substring(6))];
        if (s != null) sh.add(s);
      } else if (k == 'rules') {
        ru = rules;
      }
    }
    await api.push(students: st, sections: sc, shifts: sh, rules: ru);
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
    for (final cs in snap.students) {
      if (_dirty.contains('student:${cs.id}')) continue;
      final cur = _students[cs.id];
      if (cur == null || cs.updatedAt.isAfter(cur.updatedAt)) {
        if (cs.deleted) {
          if (cur != null) {
            _students.remove(cs.id);
            changed = true;
          }
        } else {
          _students[cs.id] = cs;
          changed = true;
        }
      }
    }
    for (final cs in snap.sections) {
      if (_dirty.contains('section:${cs.no}')) continue;
      final cur = sections[cs.no];
      if (cur == null || cs.updatedAt.isAfter(cur.updatedAt)) {
        sections[cs.no] = cs;
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
  String dayCsv(DateTime day) {
    final sb = StringBuffer('\uFEFF');
    sb.writeln('ID,Name,Section,Status,In,Out,Late (min),Early (min),Punches');
    for (final r in book.day(day)) {
      String q(String s) => '"${s.replaceAll('"', '""')}"';
      sb.writeln([
        r.student.id,
        q(r.student.name),
        q(sectionName(r.student.section)),
        statusLabel(r.status),
        r.in1 == null ? '' : fmtTime(r.in1!),
        r.out1 == null && r.out2 == null ? '' : fmtTime((r.out2 ?? r.out1)!),
        r.lateMin,
        r.earlyMin,
        r.punches,
      ].join(','));
    }
    return sb.toString();
  }

  Future<String> writeText(String path, String text) async {
    await File(path).writeAsBytes(utf8.encode(text));
    return path;
  }
}

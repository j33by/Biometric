// On-disk storage for the app's working database.
//
//   db.json     students, sections, shifts, rules, settings, sync bookkeeping
//   logs.jsonl  one punch per line, append-only (fast to extend, cheap to load)
//
// Writes are atomic (temp file + rename) so a crash or a pulled USB stick
// can never leave a half-written database behind.

import 'dart:convert';
import 'dart:io';

import '../core/models.dart';

class Persist {
  final Directory dir;
  Persist(this.dir);

  File get _db => File('${dir.path}${Platform.pathSeparator}db.json');
  File get _logs => File('${dir.path}${Platform.pathSeparator}logs.jsonl');

  Future<void> ensure() async {
    if (!await dir.exists()) await dir.create(recursive: true);
  }

  Future<Map<String, dynamic>?> loadDb() async {
    try {
      if (!await _db.exists()) return null;
      final text = await _db.readAsString();
      final j = jsonDecode(text);
      return j is Map<String, dynamic> ? j : null;
    } catch (_) {
      // Corrupt file: keep it for inspection and start clean.
      try {
        await _db.rename('${_db.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
      } catch (_) {}
      return null;
    }
  }

  Future<void> saveDb(Map<String, dynamic> json) => writeAtomic(_db, utf8.encode(jsonEncode(json)));

  Future<List<PunchLog>> loadLogs() async {
    final out = <PunchLog>[];
    if (!await _logs.exists()) return out;
    final lines = await _logs.openRead().transform(utf8.decoder).transform(const LineSplitter()).toList();
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        out.add(PunchLog.fromJson(jsonDecode(line) as Map<String, dynamic>));
      } catch (_) {
        // skip a damaged line (e.g. power cut mid-append)
      }
    }
    return out;
  }

  Future<void> appendLogs(List<PunchLog> logs) async {
    if (logs.isEmpty) return;
    final sb = StringBuffer();
    for (final l in logs) {
      sb.writeln(jsonEncode(l.toJson()));
    }
    await _logs.writeAsString(sb.toString(), mode: FileMode.append, flush: true);
  }

  static Future<void> writeAtomic(File target, List<int> bytes) async {
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      if (await target.exists()) await target.delete();
      await tmp.rename(target.path);
    }
  }
}

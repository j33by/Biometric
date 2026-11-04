// Android-only local notifications with NO Firebase / Google services.
//
// How it works: the app itself asks Supabase for new data and shows a notification on the phone.
//  * While the app is open: checks every minute.
//  * In the background: Android WorkManager wakes the app roughly every 15 minutes (Android's minimum;
//    the system may delay it further in battery saver / Doze) and runs the same check.
// What is remembered between checks lives in SharedPreferences, per user, so nothing is announced twice
// and the very first check only records the current state (no flood of old notices).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:workmanager/workmanager.dart';

import 'attendance.dart';
import 'config.dart';
import 'models.dart';
import 'ph.dart';
import 'repo.dart';

const _taskName = 'cnhs_check';
final _plugin = FlutterLocalNotificationsPlugin();
bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Entry point Android runs in the background (a separate isolate, app UI not needed).
@pragma('vm:entry-point')
void notifyBackgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      if (kSupabaseUrl.isEmpty) return true;
      await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey); // restores the saved login
      await Notify.check();
    } catch (e) {
      debugPrint('Background check failed: $e');
    }
    return true; // never ask Android to retry aggressively
  });
}

class Notify {
  static final _events = StreamController<void>.broadcast();
  static Timer? _timer;

  /// Fires when a check found something new, so open screens can refresh.
  static Stream<void> get events => _events.stream;

  static Future<void> init() async {
    if (!_android) return;
    await Workmanager().initialize(notifyBackgroundDispatcher);
  }

  static Future<void> _initPlugin() => _plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );

  /// Call after sign-in.
  static Future<void> start() async {
    if (!_android) return;
    try {
      await _initPlugin();
      await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: const Duration(minutes: 15),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        constraints: Constraints(networkType: NetworkType.connected),
      );
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 60), (_) => _foreground());
      unawaited(_foreground());
    } catch (e) {
      debugPrint('Notify.start failed: $e');
    }
  }

  /// Call before signing out: stops background checks and forgets this user's markers.
  static Future<void> stop() async {
    if (!_android) return;
    _timer?.cancel();
    try {
      await Workmanager().cancelByUniqueName(_taskName);
      final prefs = await SharedPreferences.getInstance();
      for (final k in prefs.getKeys().where((k) => k.startsWith('n_'))) {
        await prefs.remove(k);
      }
    } catch (_) {}
  }

  /// Duty reminders for a linked teacher. All times are Philippine time (the phone's own zone is
  /// ignored). Each one fires at most once per day.
  ///  - shortly before the first log-in: "Time to log in"
  ///  - once the school has imported the device and the log-in was late: "Marked late"
  ///  - after the duty ended with a log-in but no log-out: "No log-out recorded"
  static Future<void> _reminders(SharedPreferences prefs, String p, Link link, List<(String, String)> items) async {
    final now = phNow();
    final today = dayOf(now);
    final key = fDate.format(today);
    final sch = await Repo.mySchedule(link);
    final shift = sch.shiftOn(today);
    if (shift == null || sch.leaveOn(today) != null) return;
    final start = shift.times.startMin, end = shift.times.endMin;
    if (start == null || end == null) return;
    final nowMin = now.hour * 60 + now.minute;
    final punches = await Repo.logs(link.teacherId, today, today.add(const Duration(days: 1)));

    if (punches.isEmpty && nowMin >= start - 20 && nowMin <= start + sch.rules.lateAllow + 10 && prefs.getString('${p}rem_in') != key) {
      items.add(('Time to log in', 'Your duty starts at ${fmtHm12(start)}. Scan on the biometric device.'));
      await prefs.setString('${p}rem_in', key);
    }
    if (punches.isEmpty) return;
    final v = sch.view(today, punches, true, now);
    if (v.state == DayState.late && prefs.getString('${p}late') != key) {
      items.add(('Marked late today', 'You logged in ${v.lateMin} min after ${fmtHm12(start)}.'));
      await prefs.setString('${p}late', key);
    }
    if (v.attended && v.outTime == null && nowMin >= end + 10 && nowMin <= end + 240 && prefs.getString('${p}out') != key) {
      items.add(('No log-out recorded', 'Your duty ended at ${fmtHm12(end)}. Remember to scan when you leave.'));
      await prefs.setString('${p}out', key);
    }
  }

  static Future<void> _foreground() async {
    if (await check()) _events.add(null);
  }

  /// One check. Returns true if anything new was announced.
  static Future<bool> check() async {
    if (!_android || sb.auth.currentSession == null) return false;
    try {
      await _initPlugin();
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // the app and the background worker are different isolates
      final p = 'n_${Repo.uid}_';
      final first = !(prefs.getBool('${p}base') ?? false);
      final items = <(String, String)>[];

      if (await Repo.isAdmin()) {
        final keys = <String>{};
        final seen = (prefs.getStringList('${p}adm') ?? const <String>[]).toSet();
        for (final l in await Repo.links('pending')) {
          final k = 'req:${l.id}';
          keys.add(k);
          if (!first && !seen.contains(k)) items.add(('New link request', '${l.displayName} wants to link to ${l.teacherName}'));
        }
        for (final l in await Repo.links('unlink')) {
          final k = 'unl:${l.id}';
          keys.add(k);
          if (!first && !seen.contains(k)) items.add(('Unlink request', '${l.displayName} asked to unlink from ${l.teacherName}'));
        }
        await prefs.setStringList('${p}adm', keys.toList());
      } else {
        final link = await Repo.myLink();
        final status = link?.status ?? 'none';
        final last = prefs.getString('${p}status');
        if (!first && last == 'pending' && status == 'approved') {
          items.add(('Request approved', 'You can now see your schedule, log-ins and log-outs, and notices.'));
        } else if (!first && last == 'pending' && status == 'denied') {
          items.add(('Request denied', (link?.adminNote ?? '').isEmpty ? 'Open the app to pick the correct record.' : link!.adminNote));
        }
        final wasUnlink = prefs.getBool('${p}unlink') ?? false;
        if (!first && wasUnlink) {
          if (link == null || link.status != 'approved') {
            items.add(('Unlink approved', 'Open the app to link to a record again.'));
          } else if (!link.unlinkRequested) {
            items.add(('Unlink request declined', link.adminNote.isEmpty ? 'Your account stays linked.' : link.adminNote));
          }
        }
        await prefs.setString('${p}status', status);
        await prefs.setBool('${p}unlink', link != null && link.status == 'approved' && link.unlinkRequested);

        if (status == 'approved') {
          await _reminders(prefs, p, link!, items);
          final seenId = prefs.getInt('${p}notice');
          if (seenId == null || first) {
            await prefs.setInt('${p}notice', await Repo.latestNoticeId());
          } else {
            final fresh = await Repo.noticesAfter(seenId);
            if (fresh.length <= 3) {
              for (final n in fresh) {
                items.add((n.title, n.body.length > 140 ? '${n.body.substring(0, 140)}…' : n.body));
              }
            } else {
              items.add(('${fresh.length} new notices', fresh.map((n) => n.title).take(3).join(' · ')));
            }
            if (fresh.isNotEmpty) await prefs.setInt('${p}notice', fresh.last.id);
          }
        }
      }

      await prefs.setBool('${p}base', true);
      for (var i = 0; i < items.length; i++) {
        await _plugin.show(
          (DateTime.now().millisecondsSinceEpoch ~/ 1000 + i) & 0x7fffffff,
          items[i].$1,
          items[i].$2,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'cnhs_updates',
              'School updates',
              channelDescription: 'Notices, request decisions and attendance news',
              importance: Importance.high,
              priority: Priority.high,
            ),
          ),
        );
      }
      return items.isNotEmpty;
    } catch (e) {
      debugPrint('Notify.check failed: $e'); // offline etc.: just try again next time
      return false;
    }
  }
}

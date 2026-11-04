// Philippine Standard Time (UTC+8, no daylight saving) for the phone app.
//
// The biometric device, the shift times and every stored punch are plain Philippine
// wall-clock times with no time zone.  A teacher's phone may be set to any zone (or be
// travelling), so "now" and "today" are ALWAYS derived from the real UTC instant + 8 h,
// never from the phone's own zone.  The result is a plain DateTime holding Philippine
// wall-clock fields, which is exactly how punches are held, so they compare directly.

import 'package:intl/intl.dart';

const int kPhUtcOffsetHours = 8;

DateTime phNow([DateTime? at]) {
  final t = (at ?? DateTime.now()).toUtc().add(const Duration(hours: kPhUtcOffsetHours));
  return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
}

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime phToday([DateTime? at]) => dayOf(phNow(at));

final fTime = DateFormat('h:mm a');
final fDay = DateFormat('EEE, MMM d');
final fMonth = DateFormat('MMMM yyyy');
final fStamp = DateFormat('MMM d, h:mm a');
final fDate = DateFormat('yyyy-MM-dd');
final fStampSql = DateFormat('yyyy-MM-dd HH:mm:ss');

/// Minutes since midnight -> "7:50 AM".
String fmtHm12(int minutes) {
  final h24 = (minutes ~/ 60) % 24;
  final m = minutes % 60;
  final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
  return '$h12:${m.toString().padLeft(2, '0')} ${h24 >= 12 ? 'PM' : 'AM'}';
}

int? parseHm(String s) {
  final m = RegExp(r'^\s*(\d{1,2}):(\d{2})').firstMatch(s);
  if (m == null) return null;
  final h = int.parse(m.group(1)!), mi = int.parse(m.group(2)!);
  if (h > 47 || mi > 59) return null;
  return h * 60 + mi;
}

/// "07:50","09:50" -> "7:50 – 9:50 AM".
String fmtRange12(String a, String b) {
  final x = parseHm(a), y = parseHm(b);
  if (x == null || y == null) return '–';
  final xs = fmtHm12(x), ys = fmtHm12(y);
  if (xs.substring(xs.length - 2) == ys.substring(ys.length - 2)) {
    return '${xs.substring(0, xs.length - 3)} – $ys';
  }
  return '$xs – $ys';
}

String fmtMinutes(int m) {
  if (m < 60) return '$m min';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h h' : '$h h $r min';
}

/// What a person types ("7:50 am", "1:00 PM", "13:00") -> 24-hour "HH:mm", or null.
String? normalizeTimeInput(String raw) {
  String two(int n) => n.toString().padLeft(2, '0');
  final m = RegExp(r'^\s*(\d{1,2})(?::(\d{2}))?\s*([AaPp])\.?[Mm]?\.?\s*$|^\s*(\d{1,2}):(\d{2})\s*$').firstMatch(raw);
  if (m == null) return null;
  if (m.group(4) != null) {
    final h = int.parse(m.group(4)!), mi = int.parse(m.group(5)!);
    if (h > 23 || mi > 59) return null;
    return '${two(h)}:${two(mi)}';
  }
  var h = int.parse(m.group(1)!);
  final mi = m.group(2) == null ? 0 : int.parse(m.group(2)!);
  if (h < 1 || h > 12 || mi > 59) return null;
  final pm = m.group(3)!.toLowerCase() == 'p';
  if (h == 12) h = 0;
  if (pm) h += 12;
  return '${two(h)}:${two(mi)}';
}

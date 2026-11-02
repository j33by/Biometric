// Small date helpers (the app avoids the intl package on purpose).
// All device timestamps are "wall clock" local times without a zone.

const List<String> kWeekdayShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const List<String> kWeekdayLong = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday'
];
const List<String> kMonthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec'
];

String two(int n) => n < 10 ? '0$n' : '$n';

String fmtDate(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
String fmtTime(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
String fmtTimeSec(DateTime d) => '${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
String fmtDateTime(DateTime d) => '${fmtDate(d)} ${fmtTimeSec(d)}';

/// "Mon, 2 Nov 2026"
String fmtDateLong(DateTime d) =>
    '${kWeekdayShort[d.weekday % 7]}, ${d.day} ${kMonthShort[d.month - 1]} ${d.year}';

/// "2 Nov"
String fmtDayMonth(DateTime d) => '${d.day} ${kMonthShort[d.month - 1]}';

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Dart's weekday is 1=Mon..7=Sun.  The device uses 0=Sun..6=Sat.
int deviceWeekday(DateTime d) => d.weekday % 7;

final RegExp _dtRe = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})[ T]+(\d{1,2}):(\d{2})(?::(\d{2}))?');

DateTime? parseDateTime(String s) {
  final m = _dtRe.firstMatch(s);
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    m.group(6) == null ? 0 : int.parse(m.group(6)!),
  );
}

DateTime? parseDate(String s) {
  final m = RegExp(r'(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(s);
  if (m == null) return null;
  return DateTime(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

/// "HH:mm" -> minutes since midnight, or null if empty/invalid.
int? parseHm(String s) {
  final m = RegExp(r'^\s*(\d{1,2}):(\d{2})').firstMatch(s);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final mi = int.parse(m.group(2)!);
  if (h > 47 || mi > 59) return null;
  return h * 60 + mi;
}

String fmtHm(int minutes) => '${two(minutes ~/ 60)}:${two(minutes % 60)}';

String fmtDuration(int minutes) {
  if (minutes <= 0) return '0m';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

String fmtAgo(DateTime t, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final diff = n.difference(t);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  return '${diff.inDays} d ago';
}

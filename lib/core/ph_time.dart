// Philippine Standard Time (PST / "PHT", UTC+8, no daylight saving).
//
// Why this file exists
// --------------------
// The biometric device stores punches as plain wall-clock times with no time
// zone ("2026-11-03 07:48:12"), and the shift times typed into the Employee
// Form are wall-clock too ("07:50").  They only agree with each other if
// everybody means the SAME clock.  A PC, a phone or a cloud server that is set
// to another zone (Render and Supabase both run on UTC) would otherwise decide
// "today" and "is the teacher late?" differently from the device.
//
// So the whole system works on ONE rule:
//   * every wall-clock value (shift times, punch times, "today", "now")
//     is Philippine time;
//   * "now" is always derived from the real UTC instant + 8 hours, never from
//     the zone the computer or phone happens to be set to;
//   * the value is returned as a plain (non-UTC) DateTime holding the
//     Philippine wall-clock fields, which is exactly how punches are held.

import 'dates.dart';

const int kPhUtcOffsetHours = 8;
const String kPhLabel = 'Philippine Time (UTC+8)';

/// Converts a real instant to a plain DateTime holding Philippine wall-clock fields.
DateTime phFromInstant(DateTime instant) {
  final t = instant.toUtc().add(const Duration(hours: kPhUtcOffsetHours));
  return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
}

/// The current Philippine wall-clock time.  [at] lets tests pass a fixed instant.
DateTime phNow([DateTime? at]) => phFromInstant(at ?? DateTime.now());

/// Today's date in the Philippines (time of day removed).
DateTime phToday([DateTime? at]) => dateOnly(phNow(at));

/// "7:50 AM" style clock for headers.
String fmtPhClock(DateTime ph) => '${fmtTime12(ph)} PHT';

/// How far this computer's own zone is from Philippine time, in hours.
/// 0 means the computer is already on Philippine time.
int localZoneOffsetFromPhHours([DateTime? at]) {
  final now = at ?? DateTime.now();
  return now.timeZoneOffset.inMinutes ~/ 60 - kPhUtcOffsetHours;
}

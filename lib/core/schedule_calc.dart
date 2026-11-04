// SHARED FILE - the desktop app and the phone app use byte-identical copies:
//   lib/core/schedule_calc.dart  ==  teacher_app/lib/schedule_calc.dart
// (tools/check_shared.sh fails CI if they drift apart.)
//
// Pure Dart, no imports.  Given a shift, the attendance rules and one teacher's
// raw punches for ONE day, it works out In / Out, late minutes and early-leave
// minutes with the same rules as the biometric device's own report:
//   In  = first punch, Out = last distinct punch,
//   late  = In  - shift start  (when more than the late allowance),
//   early = shift end - Out    (when more than the early allowance).
// All times are Philippine wall-clock times (see ph_time.dart).

/// The six numbers of one device shift ("HH:mm" strings, empty = unused).
class ShiftTimes {
  final String in1, out1, in2, out2, otIn, otOut;
  const ShiftTimes({
    this.in1 = '',
    this.out1 = '',
    this.in2 = '',
    this.out2 = '',
    this.otIn = '',
    this.otOut = '',
  });

  bool get isEmpty => in1.isEmpty && out1.isEmpty;
  bool get hasSecondPeriod => in2.isNotEmpty && out2.isNotEmpty;
  bool get hasOvertime => otIn.isNotEmpty && otOut.isNotEmpty;

  /// First log-in time of the day, in minutes since midnight.
  int? get startMin => _hm(in1);

  /// Last log-out time of the day, in minutes since midnight.
  int? get endMin => hasSecondPeriod ? _hm(out2) : _hm(out1);
}

class RuleValues {
  final int lateAllow; // minutes
  final int earlyAllow; // minutes
  final int repeatMin; // repeated verification window, minutes
  const RuleValues({this.lateAllow = 0, this.earlyAllow = 0, this.repeatMin = 3});
}

class DayTimes {
  final DateTime? in1, out1, in2, out2;
  final int lateMin, earlyMin, otMin;
  final int punches; // after repeated scans were dropped
  final bool missedOut; // clocked in but no log-out
  const DayTimes({
    this.in1,
    this.out1,
    this.in2,
    this.out2,
    this.lateMin = 0,
    this.earlyMin = 0,
    this.otMin = 0,
    this.punches = 0,
    this.missedOut = false,
  });

  /// The last log-out of the day, whichever period it belongs to.
  DateTime? get lastOut => out2 ?? out1;
}

int? _hm(String s) {
  final m = RegExp(r'^\s*(\d{1,2}):(\d{2})').firstMatch(s);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final mi = int.parse(m.group(2)!);
  if (h > 47 || mi > 59) return null;
  return h * 60 + mi;
}

int _mins(DateTime t) => t.hour * 60 + t.minute;

/// [shift] is null on a day with no duty (shift 0): punches are still reported
/// but nothing is "late".  Returns null when there are no punches at all.
DayTimes? calcDay({
  required ShiftTimes? shift,
  required RuleValues rules,
  required List<DateTime> rawPunches,
}) {
  if (rawPunches.isEmpty) return null;

  // drop repeated verifications
  final sorted = [...rawPunches]..sort();
  final punches = <DateTime>[];
  for (final p in sorted) {
    if (punches.isNotEmpty && p.difference(punches.last).inMinutes < rules.repeatMin) continue;
    punches.add(p);
  }

  if (shift == null) {
    return DayTimes(
      in1: punches.first,
      out1: punches.length > 1 ? punches.last : null,
      punches: punches.length,
    );
  }

  // overtime window
  var regular = punches;
  var otMin = 0;
  if (shift.hasOvertime) {
    final otIn = _hm(shift.otIn)!;
    final otOut = _hm(shift.otOut)!;
    final ot = punches.where((p) => _mins(p) >= otIn - 30).toList();
    regular = punches.where((p) => _mins(p) < otIn - 30).toList();
    if (ot.length > 1) {
      final start = _mins(ot.first) > otIn ? _mins(ot.first) : otIn;
      final end = _mins(ot.last) < otOut ? _mins(ot.last) : otOut;
      if (end > start) otMin = end - start;
    }
  }

  // split into period 1 / period 2
  List<DateTime> p1 = regular, p2 = const [];
  if (shift.hasSecondPeriod) {
    final o1 = _hm(shift.out1);
    final i2 = _hm(shift.in2);
    if (o1 != null && i2 != null) {
      final mid = (o1 + i2) ~/ 2;
      p1 = regular.where((p) => _mins(p) < mid).toList();
      p2 = regular.where((p) => _mins(p) >= mid).toList();
    }
  }

  DateTime? in1, out1, in2, out2;
  if (p1.isNotEmpty) {
    in1 = p1.first;
    if (p1.length > 1) out1 = p1.last;
  }
  if (p2.isNotEmpty) {
    in2 = p2.first;
    if (p2.length > 1) out2 = p2.last;
  }

  var late = 0, early = 0;
  if (!shift.isEmpty) {
    final sIn1 = _hm(shift.in1);
    final sOut1 = _hm(shift.out1);
    if (in1 != null && sIn1 != null) {
      final v = _mins(in1) - sIn1 - rules.lateAllow;
      if (v > 0) late += _mins(in1) - sIn1;
    }
    if (out1 != null && sOut1 != null && !shift.hasSecondPeriod) {
      final v = sOut1 - rules.earlyAllow - _mins(out1);
      if (v > 0) early += sOut1 - _mins(out1);
    }
    if (shift.hasSecondPeriod) {
      final sIn2 = _hm(shift.in2);
      final sOut2 = _hm(shift.out2);
      if (in2 != null && sIn2 != null) {
        final v = _mins(in2) - sIn2 - rules.lateAllow;
        if (v > 0) late += _mins(in2) - sIn2;
      }
      final lastOut = out2 ?? out1;
      if (lastOut != null && sOut2 != null) {
        final v = sOut2 - rules.earlyAllow - _mins(lastOut);
        if (v > 0) early += sOut2 - _mins(lastOut);
      }
    }
  }

  final hasOut = shift.hasSecondPeriod ? (out2 != null || out1 != null) : out1 != null;
  return DayTimes(
    in1: in1,
    out1: out1,
    in2: in2,
    out2: out2,
    lateMin: late,
    earlyMin: early,
    otMin: otMin,
    punches: punches.length,
    missedOut: !hasOut,
  );
}

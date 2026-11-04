import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/attendance.dart';
import '../core/dates.dart';
import '../core/models.dart';
import '../core/ph_time.dart';
import 'theme.dart';

/// Flat bordered panel with an optional title row.
class Panel extends StatelessWidget {
  final String? title;
  final Widget? trailing;
  final Widget child;
  final EdgeInsets padding;
  const Panel({super.key, this.title, this.trailing, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: C.surface,
        border: Border.all(color: C.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: C.border))),
              child: Row(children: [
                Expanded(
                    child: Text(title!.toUpperCase(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: C.muted))),
                if (trailing != null) trailing!,
              ]),
            ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}

class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  const PageHeader({super.key, required this.title, this.subtitle, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: C.ink)),
            if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle!, style: const TextStyle(color: C.muted))),
          ]),
        ),
        for (final a in actions) Padding(padding: const EdgeInsets.only(left: 8), child: a),
      ]),
    );
  }
}

class Kpi extends StatelessWidget {
  final String label;
  final String value;
  final String? note;
  final Color color;
  const Kpi({super.key, required this.label, required this.value, this.note, this.color = C.ink});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      decoration: BoxDecoration(
        color: C.surface,
        border: Border.all(color: C.border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: C.muted)),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: color, height: 1.05, fontFeatures: const [FontFeature.tabularFigures()])),
        if (note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(note!, style: const TextStyle(fontSize: 12, color: C.muted))),
      ]),
    );
  }
}

class Tag extends StatelessWidget {
  final String text;
  final Color fg;
  final Color bg;
  const Tag(this.text, {super.key, required this.fg, required this.bg});

  factory Tag.status(DayStatus s) {
    switch (s) {
      case DayStatus.present:
        return Tag(statusLabel(s), fg: C.ok, bg: C.okSoft);
      case DayStatus.late:
        return Tag(statusLabel(s), fg: C.warn, bg: C.warnSoft);
      case DayStatus.absent:
        return Tag(statusLabel(s), fg: C.bad, bg: C.badSoft);
      case DayStatus.leave:
        return Tag(statusLabel(s), fg: C.accent, bg: C.accentSoft);
      case DayStatus.dayOff:
      case DayStatus.noData:
        return Tag(statusLabel(s), fg: C.muted, bg: C.surfaceAlt);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(3)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class EmptyNote extends StatelessWidget {
  final String text;
  const EmptyNote(this.text, {super.key});
  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.symmetric(vertical: 28), child: Center(child: Text(text, style: const TextStyle(color: C.muted))));
}

Future<bool> confirm(BuildContext context, String title, String body, {String action = 'Delete', bool danger = true}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SizedBox(width: 380, child: Text(body)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: C.muted))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: danger ? C.bad : C.accent),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return r ?? false;
}

void toast(BuildContext context, String msg, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      backgroundColor: error ? C.bad : C.ink,
      duration: Duration(seconds: error ? 6 : 3),
    ));
}

// ------------------------------------------------------------------ charts

/// Attendance-rate line with a soft fill. null = no data that day (gap).
class TrendChart extends StatelessWidget {
  final List<double?> values; // 0..1
  final List<String> labels;
  const TrendChart({super.key, required this.values, required this.labels});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _TrendPainter(values, labels), size: Size.infinite);
}

class _TrendPainter extends CustomPainter {
  final List<double?> v;
  final List<String> labels;
  _TrendPainter(this.v, this.labels);

  void _text(Canvas c, String s, Offset o, {TextAlign align = TextAlign.left, Color color = C.muted, double w = 60}) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontSize: 10.5, color: color, fontFamily: kFont)),
        textDirection: TextDirection.ltr,
        textAlign: align)
      ..layout(maxWidth: w);
    final dx = align == TextAlign.right ? o.dx - tp.width : (align == TextAlign.center ? o.dx - tp.width / 2 : o.dx);
    tp.paint(c, Offset(dx, o.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = 34.0, bottom = 20.0, top = 6.0;
    final w = size.width - left - 6;
    final h = size.height - bottom - top;
    final grid = Paint()
      ..color = C.border
      ..strokeWidth = 1;
    for (final g in [0.0, 0.5, 1.0]) {
      final y = top + h * (1 - g);
      canvas.drawLine(Offset(left, y), Offset(left + w, y), grid);
      _text(canvas, '${(g * 100).round()}%', Offset(left - 6, y - 7), align: TextAlign.right);
    }
    if (v.isEmpty) return;
    final n = v.length;
    double x(int i) => left + (n == 1 ? w / 2 : w * i / (n - 1));
    double y(double val) => top + h * (1 - val.clamp(0, 1));

    final line = Paint()
      ..color = C.accent
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = C.accent.withValues(alpha: 0.10);
    final dot = Paint()..color = C.accent;

    var run = <int>[];
    void flush() {
      if (run.isEmpty) return;
      final path = Path()..moveTo(x(run.first), y(v[run.first]!));
      for (final i in run.skip(1)) {
        path.lineTo(x(i), y(v[i]!));
      }
      final area = Path.from(path)
        ..lineTo(x(run.last), top + h)
        ..lineTo(x(run.first), top + h)
        ..close();
      canvas.drawPath(area, fill);
      canvas.drawPath(path, line);
      run = [];
    }

    for (var i = 0; i < n; i++) {
      if (v[i] == null) {
        flush();
      } else {
        run.add(i);
      }
    }
    flush();
    for (var i = 0; i < n; i++) {
      if (v[i] != null) canvas.drawCircle(Offset(x(i), y(v[i]!)), 2.6, dot);
    }
    final step = math.max(1, (n / 7).ceil());
    for (var i = 0; i < n; i += step) {
      _text(canvas, labels[i], Offset(x(i), size.height - 14), align: TextAlign.center, w: 50);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) => old.v != v || old.labels != labels;
}

/// 24 vertical bars (punches per hour).
class HourBars extends StatelessWidget {
  final List<int> counts;
  const HourBars({super.key, required this.counts});
  @override
  Widget build(BuildContext context) => CustomPaint(painter: _HourPainter(counts), size: Size.infinite);
}

class _HourPainter extends CustomPainter {
  final List<int> c;
  _HourPainter(this.c);
  @override
  void paint(Canvas canvas, Size size) {
    const bottom = 18.0;
    final h = size.height - bottom;
    final maxV = c.fold<int>(1, (a, b) => b > a ? b : a);
    final slot = size.width / 24;
    final p = Paint()..color = C.accent;
    final pDim = Paint()..color = C.accent.withValues(alpha: 0.35);
    canvas.drawLine(Offset(0, h), Offset(size.width, h), Paint()..color = C.border);
    for (var i = 0; i < 24; i++) {
      final bh = h * c[i] / maxV;
      if (c[i] > 0) {
        canvas.drawRect(Rect.fromLTWH(i * slot + slot * 0.18, h - bh, slot * 0.64, bh), c[i] == maxV ? p : pDim);
      }
      if (i % 3 == 0) {
        final tp = TextPainter(
            text: TextSpan(text: '${i.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 10, color: C.muted, fontFamily: kFont)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(canvas, Offset(i * slot + slot / 2 - tp.width / 2, h + 4));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HourPainter old) => old.c != c;
}

/// Present / late / absent split as a ring.
class Ring extends StatelessWidget {
  final int present, late, absent;
  final String centre;
  const Ring({super.key, required this.present, required this.late, required this.absent, required this.centre});
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _RingPainter(present, late, absent),
      child: Center(child: Text(centre, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: C.ink))),
    );
  }
}

class _RingPainter extends CustomPainter {
  final int present, late, absent;
  _RingPainter(this.present, this.late, this.absent);
  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: side - 14, height: side - 14);
    final total = present + late + absent;
    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12;
    if (total == 0) {
      canvas.drawArc(rect, 0, math.pi * 2, false, stroke(C.border));
      return;
    }
    var start = -math.pi / 2;
    void seg(int n, Color col) {
      if (n == 0) return;
      final sweep = math.pi * 2 * n / total;
      canvas.drawArc(rect, start, sweep - (total == n ? 0 : 0.03), false, stroke(col));
      start += sweep;
    }

    seg(present - late, C.ok);
    seg(late, C.warn);
    seg(absent, C.bad);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.present != present || old.late != late || old.absent != absent;
}

class RateBar extends StatelessWidget {
  final double? value;
  final double width;
  const RateBar(this.value, {super.key, this.width = 120});
  @override
  Widget build(BuildContext context) {
    final v = value;
    final color = v == null ? C.faint : (v >= 0.9 ? C.ok : (v >= 0.75 ? C.warn : C.bad));
    return SizedBox(
      width: width,
      child: Row(children: [
        Expanded(
          child: Container(
            height: 6,
            decoration: BoxDecoration(color: C.surfaceAlt, borderRadius: BorderRadius.circular(1), border: Border.all(color: C.border, width: 0.5)),
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(widthFactor: v ?? 0, child: Container(color: color)),
          ),
        ),
        SizedBox(width: 38, child: Text(v == null ? '–' : '${(v * 100).round()}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: C.muted))),
      ]),
    );
  }
}

/// Header cell + body helpers for the dense tables.
class THead extends StatelessWidget {
  final List<String> cols;
  final List<double?> widths; // null = flex
  const THead(this.cols, this.widths, {super.key});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: const BoxDecoration(color: C.surfaceAlt, border: Border(bottom: BorderSide(color: C.border))),
      child: Row(children: [
        for (var i = 0; i < cols.length; i++) _cell(Text(cols[i].toUpperCase(), style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.7, color: C.muted)), widths[i]),
      ]),
    );
  }
}

Widget _cell(Widget child, double? w) => w == null ? Expanded(child: child) : SizedBox(width: w, child: child);

Widget tcell(Widget child, double? w) => _cell(child, w);

/// A live Philippine-time clock (ticks every second). Not the computer's own zone.
class PhClock extends StatefulWidget {
  final TextStyle? style;
  final bool showSeconds;
  final bool showDate;
  const PhClock({super.key, this.style, this.showSeconds = true, this.showDate = false});
  @override
  State<PhClock> createState() => _PhClockState();
}

class _PhClockState extends State<PhClock> {
  Timer? _t;
  DateTime _now = phNow();

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = phNow());
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final h12 = _now.hour % 12 == 0 ? 12 : _now.hour % 12;
    final time = '$h12:${two(_now.minute)}${widget.showSeconds ? ':${two(_now.second)}' : ''} ${_now.hour >= 12 ? 'PM' : 'AM'}';
    final text = widget.showDate ? '${fmtDateLong(_now)}  ·  $time PHT' : '$time PHT';
    return Text(text, style: widget.style ?? const TextStyle(fontFeatures: [FontFeature.tabularFigures()]));
  }
}

/// One faculty slot's week as log-in / log-out times (Mon..Fri; Sun/Sat only when used).
class WeekTimes extends StatelessWidget {
  final Faculty faculty;
  final Map<int, Shift> shifts;
  final double fontSize;
  const WeekTimes({super.key, required this.faculty, required this.shifts, this.fontSize = 11.5});

  @override
  Widget build(BuildContext context) {
    final days = <int>[
      if (faculty.week[0] != 0) 0,
      1, 2, 3, 4, 5,
      if (faculty.week[6] != 0) 6,
    ];
    return Row(children: [
      for (final d in days)
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(right: 4),
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 5),
            decoration: BoxDecoration(color: faculty.week[d] == 0 ? C.surfaceAlt : C.accentSoft, borderRadius: BorderRadius.circular(2)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(kWeekdayShort[d], style: const TextStyle(fontSize: 9.5, color: C.muted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 1),
              Text(
                faculty.week[d] == 0 ? '–' : (shifts[faculty.week[d]]?.label ?? 'Shift ${faculty.week[d]}'),
                style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: faculty.week[d] == 0 ? C.faint : C.ink, height: 1.2),
              ),
            ]),
          ),
        ),
    ]);
  }
}

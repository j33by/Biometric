import 'dart:async';

import 'package:flutter/material.dart';

import '../attendance.dart';
import '../models.dart';
import '../ph.dart';
import '../repo.dart';

export '../ph.dart' show fTime, fDay, fMonth, fStamp, dayOf;

void toast(BuildContext c, String m, {bool error = false}) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Theme.of(c).colorScheme.error : null));
}

Future<String?> askText(BuildContext c,
    {required String title, required String label, String initial = '', int lines = 1}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (_) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctl, autofocus: true, minLines: lines, maxLines: lines + 2, decoration: InputDecoration(labelText: label)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('OK')),
      ],
    ),
  );
}

class Empty extends StatelessWidget {
  final IconData icon;
  final String text;
  const Empty(this.icon, this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 44, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 10),
            Text(text, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ]),
        ),
      );
}

/// FutureBuilder with a spinner and a readable error.
class Busy<T> extends StatelessWidget {
  final Future<T> future;
  final Widget Function(T data) builder;
  const Busy({super.key, required this.future, required this.builder});
  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
        future: future,
        builder: (c, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
          }
          if (s.hasError) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(errText(s.error!), textAlign: TextAlign.center, style: TextStyle(color: Theme.of(c).colorScheme.error)),
                  const SizedBox(height: 8),
                  TextButton(onPressed: () => signOut(), child: const Text('Sign out')),
                ]),
              ),
            );
          }
          return builder(s.data as T);
        },
      );
}

/// Shows the subject (faculty slot name) for a faculty number.
class FacultyName extends StatelessWidget {
  final int? no;
  final TextStyle? style;
  const FacultyName(this.no, {super.key, this.style});
  @override
  Widget build(BuildContext context) {
    if (no == null) return Text('—', style: style);
    return FutureBuilder<Map<int, String>>(
      future: Repo.facultyNames(),
      builder: (_, s) {
        final n = s.data?[no];
        return Text(n == null || n.isEmpty ? 'Faculty $no' : n, style: style);
      },
    );
  }
}

/// Ticking Philippine clock. Never uses the phone's own zone.
class PhClockText extends StatefulWidget {
  final TextStyle? style;
  final bool seconds;
  const PhClockText({super.key, this.style, this.seconds = true});
  @override
  State<PhClockText> createState() => _PhClockTextState();
}

class _PhClockTextState extends State<PhClockText> {
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
    final mm = _now.minute.toString().padLeft(2, '0');
    final ss = _now.second.toString().padLeft(2, '0');
    return Text('$h12:$mm${widget.seconds ? ':$ss' : ''} ${_now.hour >= 12 ? 'PM' : 'AM'}',
        style: (widget.style ?? const TextStyle()).copyWith(fontFeatures: const [FontFeature.tabularFigures()]));
  }
}

/// Re-runs [builder] every [every] so "starts in 20 min" stays true while the screen is open.
class Ticker extends StatefulWidget {
  final Duration every;
  final Widget Function(BuildContext context, DateTime phNow) builder;
  const Ticker({super.key, this.every = const Duration(seconds: 30), required this.builder});
  @override
  State<Ticker> createState() => _TickerState();
}

class _TickerState extends State<Ticker> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(widget.every, (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, phNow());
}

Color stateColor(DayState s) {
  switch (s) {
    case DayState.present:
      return const Color(0xFF2E7D32);
    case DayState.late:
      return const Color(0xFFEF6C00);
    case DayState.absent:
      return const Color(0xFFC62828);
    case DayState.leave:
      return const Color(0xFF1565C0);
    case DayState.waiting:
    case DayState.upcoming:
      return const Color(0xFF6A5ACD);
    case DayState.off:
    case DayState.noData:
      return const Color(0xFF757575);
  }
}

class StateChip extends StatelessWidget {
  final DayState state;
  final String? text;
  const StateChip(this.state, {super.key, this.text});
  @override
  Widget build(BuildContext context) {
    final c = stateColor(state);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text ?? stateLabel(state), style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class NoticeTile extends StatelessWidget {
  final Notice n;
  final Widget? trailing;
  const NoticeTile(this.n, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ExpansionTile(
          leading: Icon(n.pinned ? Icons.push_pin : Icons.campaign_outlined),
          trailing: trailing,
          title: Text(n.title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${fStamp.format(n.createdAt)}${n.faculty == null ? '' : ' · Faculty ${n.faculty}'}'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [Align(alignment: Alignment.centerLeft, child: Text(n.body.isEmpty ? '(no details)' : n.body))],
        ),
      );
}

/// Debounced name search used by teachers (sign-up) and admins (re-binding / rename).
class TeacherPicker extends StatefulWidget {
  final Future<List<TeacherRow>> Function(String q) search;
  final void Function(TeacherRow s) onPick;
  final bool loadOnStart;
  const TeacherPicker({super.key, required this.search, required this.onPick, this.loadOnStart = false});
  @override
  State<TeacherPicker> createState() => _TeacherPickerState();
}

class _TeacherPickerState extends State<TeacherPicker> {
  final _ctl = TextEditingController();
  Timer? _t;
  Future<List<TeacherRow>>? _f;

  @override
  void initState() {
    super.initState();
    if (widget.loadOnStart) _f = widget.search('');
  }

  @override
  void dispose() {
    _t?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      setState(() => _f = (v.trim().length < 2 && !widget.loadOnStart) ? null : widget.search(v));
    });
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        TextField(
          controller: _ctl,
          onChanged: _changed,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search teacher name', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _f == null
              ? const Empty(Icons.badge_outlined, 'Type at least 2 letters of your name.')
              : Busy<List<TeacherRow>>(
                  future: _f!,
                  builder: (rows) => rows.isEmpty
                      ? const Empty(Icons.person_search, 'No match. Check the spelling, or ask the school office to add you.')
                      : ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (c, i) => ListTile(
                            leading: CircleAvatar(child: Text(rows[i].name.isEmpty ? '?' : rows[i].name[0].toUpperCase())),
                            title: Text(rows[i].name),
                            subtitle: Row(children: [Text('ID ${rows[i].id} · '), Flexible(child: FacultyName(rows[i].faculty))]),
                            onTap: () => widget.onPick(rows[i]),
                          ),
                        ),
                ),
        ),
      ]);
}

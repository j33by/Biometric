import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import '../repo.dart';

final fTime = DateFormat('h:mm a');
final fDay = DateFormat('EEE, MMM d');
final fMonth = DateFormat('MMMM yyyy');
final fStamp = DateFormat('MMM d, h:mm a');

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

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

class SectionName extends StatelessWidget {
  final int? no;
  final TextStyle? style;
  const SectionName(this.no, {super.key, this.style});
  @override
  Widget build(BuildContext context) {
    if (no == null) return Text('—', style: style);
    return FutureBuilder<Map<int, String>>(
      future: Repo.sections(),
      builder: (_, s) {
        final n = s.data?[no];
        return Text(n == null || n.isEmpty ? 'Section $no' : n, style: style);
      },
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
          subtitle: Text('${fStamp.format(n.createdAt)}${n.section == null ? '' : ' · Section ${n.section}'}'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [Align(alignment: Alignment.centerLeft, child: Text(n.body.isEmpty ? '(no details)' : n.body))],
        ),
      );
}

/// Debounced name search used by students (sign-up) and admins (re-binding).
class StudentPicker extends StatefulWidget {
  final Future<List<StudentRow>> Function(String q) search;
  final void Function(StudentRow s) onPick;
  final bool loadOnStart;
  const StudentPicker({super.key, required this.search, required this.onPick, this.loadOnStart = false});
  @override
  State<StudentPicker> createState() => _StudentPickerState();
}

class _StudentPickerState extends State<StudentPicker> {
  final _ctl = TextEditingController();
  Timer? _t;
  Future<List<StudentRow>>? _f;

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
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Search your name', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _f == null
              ? const Empty(Icons.badge_outlined, 'Type at least 2 letters of your name.')
              : Busy<List<StudentRow>>(
                  future: _f!,
                  builder: (rows) => rows.isEmpty
                      ? const Empty(Icons.person_search, 'No match. Check the spelling, or ask your adviser to add you.')
                      : ListView.separated(
                          itemCount: rows.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (c, i) => ListTile(
                            leading: CircleAvatar(child: Text(rows[i].name.isEmpty ? '?' : rows[i].name[0].toUpperCase())),
                            title: Text(rows[i].name),
                            subtitle: Row(children: [Text('ID ${rows[i].id} · '), SectionName(rows[i].section)]),
                            onTap: () => widget.onPick(rows[i]),
                          ),
                        ),
                ),
        ),
      ]);
}

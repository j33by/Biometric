import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../notify.dart';
import '../repo.dart';
import 'common.dart';
import 'student_shell.dart';

/// Decides what a signed-in student sees: find-your-name, waiting, or the app.
class StudentGate extends StatefulWidget {
  const StudentGate({super.key});
  @override
  State<StudentGate> createState() => _StudentGateState();
}

class _StudentGateState extends State<StudentGate> {
  late Future<Link?> _f = Repo.myLink();
  void _reload() => setState(() => _f = Repo.myLink());
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = Notify.events.listen((_) => _reload()); // approved / denied / unlink decided while the app is open
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Busy<Link?>(
        future: _f,
        builder: (l) {
          if (l == null || l.status == 'denied') return LinkPage(denied: l, onChanged: _reload);
          if (l.status == 'pending') return PendingPage(link: l, onChanged: _reload);
          return StudentShell(link: l, onReload: _reload);
        },
      );
}

class LinkPage extends StatelessWidget {
  final Link? denied;
  final VoidCallback onChanged;
  const LinkPage({super.key, this.denied, required this.onChanged});

  Future<void> _pick(BuildContext context, StudentRow s) async {
    final ctl = TextEditingController(text: s.name);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Link to this record?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${s.name}  (ID ${s.id})', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('An administrator must approve this before you can see attendance.'),
          const SizedBox(height: 14),
          TextField(controller: ctl, decoration: const InputDecoration(labelText: 'Name shown on your account')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Send request')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.request(s, ctl.text.trim().isEmpty ? s.name : ctl.text);
      onChanged();
    } catch (e) {
      if (context.mounted) toast(context, errText(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Find your name'), actions: [
          IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: () => signOut()),
        ]),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (denied != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Your last request was denied.${denied!.adminNote.isEmpty ? '' : '\nReason: ${denied!.adminNote}'}\nSearch again and pick the correct record.'),
                ),
              ),
            const Text('Search the name registered with the biometric device and link it to your account.'),
            const SizedBox(height: 12),
            Expanded(child: StudentPicker(search: Repo.search, onPick: (s) => _pick(context, s))),
          ]),
        ),
      );
}

class PendingPage extends StatelessWidget {
  final Link link;
  final VoidCallback onChanged;
  const PendingPage({super.key, required this.link, required this.onChanged});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Waiting for approval'), actions: [
          IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: () => signOut()),
        ]),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.hourglass_top, size: 56),
              const SizedBox(height: 12),
              Text(link.displayName, style: Theme.of(context).textTheme.titleLarge),
              Text('Requested ${fStamp.format(link.createdAt)} · ID ${link.studentId}'),
              const SizedBox(height: 12),
              const Text('An administrator will review your request. Check back soon.', textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(onPressed: onChanged, icon: const Icon(Icons.refresh), label: const Text('Check status')),
              TextButton(
                onPressed: () async {
                  try {
                    await Repo.cancelRequest();
                    onChanged();
                  } catch (e) {
                    if (context.mounted) toast(context, errText(e), error: true);
                  }
                },
                child: const Text('Cancel request / pick a different name'),
              ),
            ]),
          ),
        ),
      );
}

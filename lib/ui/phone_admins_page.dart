import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

/// Who has the admin screens in the phone app (Supabase `app_admins`). Superadmin only.
/// Replaces running `insert into app_admins ...` in the Supabase SQL Editor.
class PhoneAdminsPage extends StatefulWidget {
  const PhoneAdminsPage({super.key});
  @override
  State<PhoneAdminsPage> createState() => _PhoneAdminsPageState();
}

class _PhoneAdminsPageState extends State<PhoneAdminsPage> {
  List<PhoneAdmin>? _admins;
  String? _error;
  bool _loading = false;
  final _email = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final app = context.app;
    if (!app.cloudEnabled) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final l = await app.api.listPhoneAdmins();
      if (mounted) setState(() => _admins = l);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Returns true if the action succeeded. The list is reloaded either way.
  Future<bool> _run(Future<void> Function() job, String done) async {
    var ok = false;
    try {
      await job();
      ok = true;
      if (mounted) toast(context, done);
    } on ApiException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    }
    await _load();
    return ok;
  }

  Future<void> _add() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      toast(context, 'Enter the email the person used to sign up in the phone app.', error: true);
      return;
    }
    final ok = await _run(() => context.app.api.addPhoneAdmin(email), 'Made $email a phone admin');
    if (ok && mounted) _email.clear();
  }

  Future<void> _remove(PhoneAdmin a) async {
    final ok = await confirm(
      context,
      'Remove ${a.email}?',
      'They lose the admin screens in the phone app the next time they open it. Their own teacher account, if any, is not affected.',
      action: 'Remove',
    );
    if (!ok || !mounted) return;
    await _run(() => context.app.api.removePhoneAdmin(a.userId), 'Removed ${a.email}');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.cloudEnabled) {
      return const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        PageHeader(title: 'Phone admins'),
        Panel(child: Text('Phone admins are stored in the cloud. Sign in to the server (not offline mode) to manage them.', style: TextStyle(color: C.muted))),
      ]);
    }
    final list = _admins ?? const <PhoneAdmin>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      PageHeader(
        title: 'Phone admins',
        subtitle: 'People who see the admin screens (Today, Requests, Teachers, Schedule, Notices) in the phone app',
        actions: [
          OutlinedButton.icon(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh, size: 16), label: const Text('Refresh')),
        ],
      ),
      Panel(
        title: 'Add a phone admin',
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              onSubmitted: (_) => _add(),
              decoration: const InputDecoration(labelText: 'Email used to sign up in the phone app', helperText: 'They must have signed up in the phone app first.'),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(onPressed: _add, icon: const Icon(Icons.person_add_alt, size: 16), label: const Text('Make admin')),
        ]),
      ),
      const SizedBox(height: 14),
      if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: const TextStyle(color: C.bad))),
      Expanded(
        child: Container(
          decoration: BoxDecoration(color: C.surface, border: Border.all(color: C.border), borderRadius: BorderRadius.circular(4)),
          child: Column(children: [
            const THead(['Email', ''], [null, 80]),
            Expanded(
              child: _loading && _admins == null
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : list.isEmpty
                      ? const EmptyNote('No phone admins yet.')
                      : ListView.builder(
                          itemCount: list.length,
                          itemBuilder: (c, i) {
                            final a = list[i];
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(color: i.isOdd ? C.surfaceAlt : C.surface, border: const Border(bottom: BorderSide(color: C.border, width: 0.5))),
                              child: Row(children: [
                                tcell(Text(a.email.isEmpty ? '(account removed)' : a.email, style: const TextStyle(fontWeight: FontWeight.w600)), null),
                                tcell(
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton(
                                      tooltip: 'Remove admin access',
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.person_remove_outlined, size: 18, color: C.bad),
                                      onPressed: () => _remove(a),
                                    ),
                                  ),
                                  80,
                                ),
                              ]),
                            );
                          },
                        ),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 20),
    ]);
  }
}

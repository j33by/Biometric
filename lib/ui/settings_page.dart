import 'package:flutter/material.dart';

import '../core/dates.dart';
import '../main.dart';
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _url = TextEditingController(text: context.app.serverUrl);
  String? _result;
  bool _busy = false;

  Future<void> _test() async {
    final app = context.app;
    setState(() {
      _busy = true;
      _result = null;
    });
    await app.setServerUrl(_url.text);
    final ok = await app.api.health();
    if (mounted) {
      setState(() {
        _busy = false;
        _result = ok ? 'Server reachable.' : 'Could not reach the server. Check the address (a free Render server may still be waking up – try again).';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      const PageHeader(title: 'Settings'),
      Panel(
        title: 'Cloud server',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: TextField(controller: _url, decoration: const InputDecoration(labelText: 'Server address', hintText: 'https://your-app.onrender.com'))),
            const SizedBox(width: 10),
            OutlinedButton(onPressed: _busy ? null : _test, child: _busy ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Test connection')),
          ]),
          if (_result != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_result!, style: TextStyle(color: _result!.startsWith('Server') ? C.ok : C.bad))),
          const SizedBox(height: 14),
          Row(children: [
            Text(app.localMode ? 'Working offline. Sign out and sign in to a server to enable cloud sync.' : (app.cloudEnabled ? 'Signed in as ${app.admin?.email}. Last sync: ${app.lastCloudSync == null ? 'not yet' : fmtAgo(app.lastCloudSync!)}.' : 'Not signed in to the cloud.'),
                style: const TextStyle(color: C.muted)),
            const Spacer(),
            if (app.cloudEnabled) OutlinedButton(onPressed: app.syncNow, child: const Text('Sync now')),
          ]),
          if (app.syncError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(app.syncError!, style: const TextStyle(color: C.bad))),
        ]),
      ),
      const SizedBox(height: 14),
      Panel(
        title: 'Account',
        child: Row(children: [
          Expanded(child: Text('${app.admin?.name.isNotEmpty == true ? app.admin!.name : app.admin?.email}  ·  ${app.admin?.role}', style: const TextStyle(fontWeight: FontWeight.w600))),
          OutlinedButton(onPressed: app.signOut, child: const Text('Sign out')),
        ]),
      ),
      const SizedBox(height: 14),
      const Panel(
        title: 'How your data is kept',
        child: Text(
          'Everything is saved on this computer first (so the dashboard works with no internet), mirrored to Supabase when the server is reachable, and written to Employee Form.xls for the device.\n'
          'Punch records are identified by teacher ID + date/time + device, so importing the same file twice – or from two computers – never creates duplicates.',
          style: TextStyle(color: C.muted, height: 1.5),
        ),
      ),
    ]);
  }
}

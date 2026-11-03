import 'package:flutter/material.dart';

import '../data/api_client.dart';
import '../main.dart';
import 'theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _url = TextEditingController();
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _init = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      _init = true;
      _url.text = context.app.serverUrl;
    }
  }

  Future<void> _signIn() async {
    final app = context.app;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await app.setServerUrl(_url.text);
      await app.signIn(_email.text, _pass.text);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(children: [
        Expanded(
          flex: 5,
          child: Container(
            color: C.side,
            padding: const EdgeInsets.all(48),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
              const Text('Attendance\nConsole', style: TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.w300, height: 1.1)),
              const SizedBox(height: 14),
              const Text(
                'Teachers attendance from the biometric device,\nkept in step with Excel, USB and the cloud.',
                style: TextStyle(color: C.sideText, fontSize: 14, height: 1.5),
              ),
            ]),
          ),
        ),
        Expanded(
          flex: 4,
          child: Center(
            child: SizedBox(
              width: 340,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Sign in', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),
                TextField(controller: _url, decoration: const InputDecoration(labelText: 'Server address', hintText: 'https://your-app.onrender.com')),
                const SizedBox(height: 12),
                TextField(controller: _email, decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  onSubmitted: (_) => _busy ? null : _signIn(),
                ),
                if (_error != null)
                  Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: C.bad, fontSize: 12.5))),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _signIn,
                  child: _busy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Sign in'),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('A free Render server can take up to a minute to wake up.', style: TextStyle(fontSize: 12, color: C.muted)),
                  ),
                const SizedBox(height: 10),
                OutlinedButton(onPressed: _busy ? null : context.app.useLocalMode, child: const Text('Work offline on this computer')),
                const SizedBox(height: 8),
                const Text(
                  'Offline mode keeps everything on this PC. You can sign in to the cloud later without losing data.',
                  style: TextStyle(fontSize: 12, color: C.muted),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

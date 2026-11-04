import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';
import '../repo.dart';
import 'common.dart';

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _signUp = false;
  bool _busy = false;
  bool _hide = true;

  Future<void> _run(Future<void> Function() job) async {
    setState(() => _busy = true);
    try {
      await job();
    } on AuthException catch (e) {
      if (mounted) toast(context, e.message, error: true);
    } catch (e) {
      if (mounted) toast(context, errText(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submit() => _run(() async {
        final email = _email.text.trim();
        final pass = _pass.text;
        if (email.isEmpty || pass.length < 6) {
          toast(context, 'Enter your email and a password of at least 6 characters.', error: true);
          return;
        }
        if (_signUp) {
          final r = await sb.auth.signUp(email: email, password: pass, emailRedirectTo: kIsWeb ? null : kOAuthRedirect);
          if (r.session == null && mounted) {
            toast(context, 'Account created. Check your email to confirm, then sign in.');
            setState(() => _signUp = false);
          }
        } else {
          await sb.auth.signInWithPassword(email: email, password: pass);
        }
      });

  Future<void> _google() => _run(() async {
        await sb.auth.signInWithOAuth(OAuthProvider.google, redirectTo: kIsWeb ? null : kOAuthRedirect);
      });

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      toast(context, 'Type your email first.', error: true);
      return;
    }
    await _run(() async {
      await sb.auth.resetPasswordForEmail(email, redirectTo: kIsWeb ? null : kOAuthRedirect);
      if (mounted) toast(context, 'Password reset email sent.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: ClipOval(child: Image.asset('assets/images/cnhs_logo.png', width: 96, height: 96, fit: BoxFit.cover))),
                const SizedBox(height: 8),
                Text('CNHS Teacher App', textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(_signUp ? 'Create your account' : 'Sign in to see your schedule and attendance',
                    textAlign: TextAlign.center, style: TextStyle(color: cs.outline)),
                const SizedBox(height: 24),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _google,
                  icon: const Icon(Icons.g_mobiledata, size: 28),
                  label: const Text('Continue with Google'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                ),
                const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.all(8), child: Text('or')), Expanded(child: Divider())])),
                TextField(controller: _email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.email], decoration: const InputDecoration(labelText: 'Email')),
                const SizedBox(height: 12),
                TextField(
                  controller: _pass,
                  obscureText: _hide,
                  onSubmitted: (_) => _submit(),
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(labelText: 'Password', suffixIcon: IconButton(icon: Icon(_hide ? Icons.visibility : Icons.visibility_off), onPressed: () => setState(() => _hide = !_hide))),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: _busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(_signUp ? 'Sign up' : 'Sign in'),
                ),
                TextButton(onPressed: _busy ? null : () => setState(() => _signUp = !_signUp), child: Text(_signUp ? 'Already have an account? Sign in' : 'New here? Create an account')),
                if (!_signUp) TextButton(onPressed: _busy ? null : _forgot, child: const Text('Forgot password?')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

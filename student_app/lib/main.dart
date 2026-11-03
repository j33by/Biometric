import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'notify.dart';
import 'repo.dart';
import 'ui/admin_shell.dart';
import 'ui/auth_page.dart';
import 'ui/common.dart';
import 'ui/student_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kSupabaseUrl.isNotEmpty) {
    await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
  }
  await Notify.init();
  runApp(const CnhsApp());
}

class CnhsApp extends StatelessWidget {
  const CnhsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'CNHS Student App',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: const Color(0xFF1D4ED8),
          inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
        ),
        home: kSupabaseUrl.isEmpty ? const _SetupNeeded() : const _AuthGate(),
      );
}

class _SetupNeeded extends StatelessWidget {
  const _SetupNeeded();
  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Empty(Icons.settings_outlined,
            'Supabase is not configured.\nRun with --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...'),
      );
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();
  @override
  Widget build(BuildContext context) => StreamBuilder<AuthState>(
        stream: sb.auth.onAuthStateChange,
        builder: (context, _) {
          final s = sb.auth.currentSession;
          if (s == null) return const AuthPage();
          return _RoleGate(key: ValueKey(s.user.id));
        },
      );
}

class _RoleGate extends StatefulWidget {
  const _RoleGate({super.key});
  @override
  State<_RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<_RoleGate> {
  final Future<bool> _admin = Repo.isAdmin();

  @override
  void initState() {
    super.initState();
    Notify.start();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Busy<bool>(future: _admin, builder: (a) => a ? const AdminShell() : const StudentGate()),
      );
}

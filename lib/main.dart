import 'package:flutter/material.dart';

import 'data/app_state.dart';
import 'ui/login_page.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BiometricApp());
}

/// Makes the [AppState] available to every page via `context.app`.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child}) : super(notifier: state);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope missing');
    return scope!.notifier!;
  }
}

extension AppContext on BuildContext {
  AppState get app => AppScope.of(this);
}

class BiometricApp extends StatefulWidget {
  const BiometricApp({super.key});
  @override
  State<BiometricApp> createState() => _BiometricAppState();
}

class _BiometricAppState extends State<BiometricApp> {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    _state.init();
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: _state,
      child: MaterialApp(
        title: 'Attendance Console',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const _Gate(),
      ),
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    if (!app.loaded) {
      return const Scaffold(body: Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3))));
    }
    if (app.fatalError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text('The app could not start:\n\n${app.fatalError}', style: const TextStyle(color: C.bad)),
          ),
        ),
      );
    }
    return app.signedIn ? const Shell() : const LoginPage();
  }
}

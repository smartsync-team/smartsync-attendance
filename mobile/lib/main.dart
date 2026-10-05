import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'screens/auth/login_screen.dart';
import 'screens/staff/staff_shell.dart';
import 'screens/student/student_shell.dart';
import 'services/app_state.dart';
import 'services/device_service.dart';
import 'services/session_controller.dart';
import 'services/sync_service.dart';
import 'theme.dart';
import 'widgets/common.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!AppConfig.isConfigured) {
    runApp(const _NotConfiguredApp());
    return;
  }
  await Supabase.initialize(url: AppConfig.supabaseUrl, publishableKey: AppConfig.supabaseKey);

  final sync = SyncService();
  await sync.init();
  final device = DeviceService();
  final session = SessionController(device, sync);
  await session.restore();

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider(create: (_) => AppState()),
      ChangeNotifierProvider.value(value: sync),
      ChangeNotifierProvider.value(value: device),
      ChangeNotifierProvider.value(value: session),
    ],
    child: const AttendanceApp(),
  ));
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Attendance',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        builder: (context, child) => _PhoneFrame(child: child!),
        home: const AuthGate(),
      );
}

/// On a wide browser window, show the app at phone size so the demo looks real.
class _PhoneFrame extends StatelessWidget {
  const _PhoneFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (size.width < 600) return child;
    final height = size.height - 40 < 860 ? size.height - 40 : 860.0;
    return ColoredBox(
      color: const Color(0xFF0E1322),
      child: Center(
        child: Container(
          width: 400,
          height: height,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: const Color(0xFF05070E), borderRadius: BorderRadius.circular(44)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(34),
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(size: Size(380, height - 20)),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Picks the first screen from the sign-in state and role.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (!app.signedIn) return const LoginScreen();
    if (app.loading && app.profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (app.profile == null) {
      return Scaffold(
        body: ErrorView(app.error ?? 'Could not load your account.', onRetry: app.refresh),
        floatingActionButton: TextButton(onPressed: app.signOut, child: const Text('Sign out')),
      );
    }
    return app.profile!.isStaff ? const StaffShell() : const StudentShell();
  }
}

class _NotConfiguredApp extends StatelessWidget {
  const _NotConfiguredApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(24),
            child: Center(
              child: Text(
                'Supabase is not configured.\n\nCopy env.example.json to env.json, fill in your '
                'project URL and publishable key, then run:\n\nflutter run --dart-define-from-file=env.json',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
}

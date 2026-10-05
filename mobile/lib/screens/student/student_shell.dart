import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../widgets/common.dart';
import '../../widgets/qr_scan_screen.dart';
import 'my_qr_screen.dart';
import 'student_home_screen.dart';
import 'student_register_screen.dart';

class StudentShell extends StatefulWidget {
  const StudentShell({super.key});

  @override
  State<StudentShell> createState() => _StudentShellState();
}

class _StudentShellState extends State<StudentShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (app.student == null) return const StudentRegisterScreen();

    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        StudentHomeScreen(onShowQr: () => setState(() => _tab = 1)),
        const MyQrScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.qr_code_2_outlined), selectedIcon: Icon(Icons.qr_code_2), label: 'My QR'),
        ],
      ),
    );
  }
}

/// Scan a course join QR (or type the course code). Returns the course, or null.
Future<Course?> pickCourse(BuildContext context, {required String hint}) async {
  final raw = await Navigator.push<String>(
    context,
    MaterialPageRoute(
      builder: (_) => QrScanScreen(title: 'Join course', hint: hint, manualLabel: 'Or type the course code'),
    ),
  );
  if (raw == null || raw.isEmpty || !context.mounted) return null;
  final id = QrCodes.parseCourse(raw);
  final course = await withProgress(
    context,
    'Finding course…',
    () => id != null ? Api.courseById(id) : Api.courseByCode(raw),
  );
  if (course == null && context.mounted) toast(context, 'Course not found. Check the QR code or course code.');
  return course;
}

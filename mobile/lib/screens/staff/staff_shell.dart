import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/session_controller.dart';
import 'home_screen.dart';
import 'live_session_screen.dart';
import 'records_screen.dart';
import 'session_setup_screen.dart';
import 'students_screen.dart';

/// Bottom navigation for lecturers and admins (matches the prototype).
class StaffShell extends StatefulWidget {
  const StaffShell({super.key});

  @override
  State<StaffShell> createState() => _StaffShellState();
}

class _StaffShellState extends State<StaffShell> {
  int _tab = 0;

  void _go(int tab) => setState(() => _tab = tab);

  @override
  Widget build(BuildContext context) {
    final live = context.select<SessionController, bool>((s) => s.active != null);
    return Scaffold(
      body: IndexedStack(index: _tab, children: [
        StaffHomeScreen(onGoTab: _go),
        live ? const LiveSessionScreen() : const SessionSetupScreen(),
        const StudentsScreen(),
        const RecordsScreen(),
      ]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _go,
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
            icon: Badge(isLabelVisible: live, smallSize: 8, child: const Icon(Icons.timer_outlined)),
            selectedIcon: const Icon(Icons.timer),
            label: 'Session',
          ),
          const NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Students'),
          const NavigationDestination(icon: Icon(Icons.assignment_outlined), selectedIcon: Icon(Icons.assignment), label: 'Records'),
        ],
      ),
    );
  }
}

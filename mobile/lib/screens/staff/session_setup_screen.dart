import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../services/device_service.dart';
import '../../services/session_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'connect_device_screen.dart';

class SessionSetupScreen extends StatefulWidget {
  const SessionSetupScreen({super.key});

  @override
  State<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends State<SessionSetupScreen> {
  String? _courseId;
  String _type = 'lecture';
  int _lateAfter = 15;

  Future<void> _start() async {
    final app = context.read<AppState>();
    final controller = context.read<SessionController>();
    final course = app.courses.where((c) => c.id == _courseId).firstOrNull;
    if (course == null) {
      toast(context, 'Pick a course first.');
      return;
    }

    final status = ValueNotifier<(String, double?)>(('Starting…', null));
    // This screen is replaced by the live screen on success, so keep these.
    final nav = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Preparing device'),
          content: ValueListenableBuilder<(String, double?)>(
            valueListenable: status,
            builder: (_, s, _) => Column(mainAxisSize: MainAxisSize.min, children: [
              LinearProgressIndicator(value: s.$2),
              const SizedBox(height: 14),
              Text(s.$1),
            ]),
          ),
        ),
      ),
    );
    try {
      await controller.start(
        course: course,
        type: _type,
        lateAfterMin: _lateAfter,
        onProgress: (m, p) => status.value = (m, p),
      );
      nav.pop();
    } catch (e) {
      nav.pop();
      messenger.showSnackBar(SnackBar(content: Text(errorText(e)), behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final device = context.watch<DeviceService>();
    final controller = context.watch<SessionController>();
    if (controller.preselectedCourseId != null) {
      _courseId = controller.preselectedCourseId;
      controller.preselectedCourseId = null;
    }
    _courseId ??= app.courses.length == 1 ? app.courses.first.id : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Start attendance')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          const Muted('Pick the class. The device loads its students and switches to verify mode.'),
          const SizedBox(height: 14),
          CourseDropdown(courses: app.courses, value: _courseId, onChanged: (v) => setState(() => _courseId = v)),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Session type'),
            items: const [
              DropdownMenuItem(value: 'lecture', child: Text('Lecture')),
              DropdownMenuItem(value: 'lab', child: Text('Lab')),
              DropdownMenuItem(value: 'tutorial', child: Text('Tutorial')),
            ],
            onChanged: (v) => setState(() => _type = v!),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _lateAfter,
            decoration: const InputDecoration(labelText: 'Mark late after'),
            items: const [
              DropdownMenuItem(value: 10, child: Text('10 minutes')),
              DropdownMenuItem(value: 15, child: Text('15 minutes')),
              DropdownMenuItem(value: 30, child: Text('30 minutes')),
              DropdownMenuItem(value: 60, child: Text('60 minutes')),
            ],
            onChanged: (v) => setState(() => _lateAfter = v!),
          ),
          const SizedBox(height: 18),
          if (!device.isConnected)
            Card(
              child: ListTile(
                leading: Icon(Icons.bluetooth_disabled, color: AppColors.of(context).warn),
                title: const Text('No device connected'),
                subtitle: const Text('Connect the fingerprint device to start.'),
                trailing: TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectDeviceScreen())),
                  child: const Text('Connect'),
                ),
              ),
            ),
          FilledButton(
            onPressed: device.isConnected && _courseId != null ? _start : null,
            child: const Text('Start session'),
          ),
        ],
      ),
    );
  }
}

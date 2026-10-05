import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../services/device_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'connect_device_screen.dart';
import 'register_flow.dart';

enum _Phase { ready, capturing, saving, done, failed }

/// Step 3: the device captures the finger 3 times and returns a template,
/// which is saved against the student in the database.
class EnrollScreen extends StatefulWidget {
  const EnrollScreen({super.key, required this.student});
  final Student student;

  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  late final DeviceService _device = context.read<DeviceService>();
  StreamSubscription<Map<String, dynamic>>? _sub;
  _Phase _phase = _Phase.ready;
  int _captured = 0;
  String _message = 'Ask the student to place the same finger on the device 3 times.';

  @override
  void dispose() {
    _sub?.cancel();
    if (_phase == _Phase.capturing) _device.send({'cmd': 'CANCEL'}).catchError((_) {});
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Phase.capturing;
      _captured = 0;
      _message = 'Place finger on the sensor (1 of 3)';
    });
    await _sub?.cancel();
    _sub = _device.events.listen(_onEvent);
    try {
      await _device.send({'cmd': 'ENROLL'});
    } catch (e) {
      _fail(errorText(e));
    }
  }

  void _onEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    switch (e['evt']) {
      case 'PLACE':
        setState(() => _message = 'Place finger on the sensor (${e['n']} of 3)');
      case 'CAPTURE':
        setState(() {
          _captured = (e['n'] as num).toInt();
          _message = _captured < 3 ? 'Got it. Lift your finger.' : 'Checking…';
        });
      case 'LIFT':
        setState(() => _message = 'Lift finger, then place it again');
      case 'POOR_IMAGE':
        setState(() => _message = 'Image unclear. Lift, wipe the finger, and press flat again.');
      case 'ENROLL_OK':
        _save(e['tpl'] as String);
      case 'ENROLL_FAIL':
        _fail(switch (e['reason']) {
          'mismatch' => 'The captures did not match. Use the same finger and press flat.',
          'verify' => 'Third capture did not match. Try again.',
          'timeout' => 'Timed out waiting for a finger.',
          _ => 'Enrollment failed (${e['reason']}).',
        });
      case 'ERROR':
        _fail(e['msg']?.toString() ?? 'Device error');
    }
  }

  void _fail(String message) {
    _sub?.cancel();
    setState(() {
      _phase = _Phase.failed;
      _message = message;
    });
  }

  Future<void> _save(String template) async {
    await _sub?.cancel();
    setState(() {
      _phase = _Phase.saving;
      _captured = 3;
      _message = 'Saving fingerprint…';
    });
    try {
      await Api.saveFingerprint(studentId: widget.student.id, templateB64: template, deviceId: _device.info?.id);
      if (mounted) setState(() => _phase = _Phase.done);
    } catch (e) {
      _fail('Captured, but could not save: ${errorText(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DeviceService>();
    final c = AppColors.of(context);

    if (_phase == _Phase.done) return _done(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Enroll fingerprint')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          Muted('Step 3 of 3 · ${widget.student.fullName} (${widget.student.regNo})'),
          const SizedBox(height: 14),
          if (!d.isConnected)
            Card(
              child: ListTile(
                leading: Icon(Icons.bluetooth_disabled, color: c.warn),
                title: const Text('Fingerprint device not connected'),
                trailing: TextButton(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectDeviceScreen())),
                  child: const Text('Connect'),
                ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(children: [
                FingerprintGraphic(step: _captured),
                const SizedBox(height: 8),
                StepBars(done: _captured),
                const SizedBox(height: 12),
                Text(_message, textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: _phase == _Phase.failed ? c.warn : null)),
                const SizedBox(height: 4),
                const Muted('The device captures the print; the app shows progress.', align: TextAlign.center, size: 12),
              ]),
            ),
          ),
          if (_phase == _Phase.ready || _phase == _Phase.failed)
            FilledButton(
              onPressed: d.isConnected ? _start : null,
              child: Text(_phase == _Phase.failed ? 'Try again' : 'Start enrollment'),
            ),
          if (_phase == _Phase.capturing && d.isSimulated)
            FilledButton.tonal(onPressed: d.simulateFinger, child: const Text('Simulate finger placed')),
          if (_phase == _Phase.capturing) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                _device.send({'cmd': 'CANCEL'}).catchError((_) {});
                _sub?.cancel();
                setState(() {
                  _phase = _Phase.ready;
                  _captured = 0;
                  _message = 'Cancelled.';
                });
              },
              child: const Text('Cancel'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _done(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
        children: [
          Icon(Icons.check_circle_outline, size: 84, color: c.ok),
          const SizedBox(height: 8),
          const Text('Student registered', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Muted('Fingerprint is now linked to ${widget.student.regNo}.', align: TextAlign.center),
          const SizedBox(height: 16),
          Card(
            child: Column(children: [
              ListTile(title: const Text('Name'), trailing: Text(widget.student.fullName)),
              const Divider(),
              ListTile(title: const Text('Reg. number'), trailing: Text(widget.student.regNo)),
              const Divider(),
              const ListTile(title: Text('Stored in'), trailing: Text('Database')),
            ]),
          ),
          FilledButton(
            onPressed: () {
              final nav = Navigator.of(context);
              nav.pop();
              startRegisterFlow(nav.context);
            },
            child: const Text('Register another student'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }
}

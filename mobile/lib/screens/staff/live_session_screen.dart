import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../services/device_service.dart';
import '../../services/session_controller.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'connect_device_screen.dart';
import 'session_summary_screen.dart';

class LiveSessionScreen extends StatefulWidget {
  const LiveSessionScreen({super.key});

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  StreamSubscription<String>? _msgSub;

  @override
  void initState() {
    super.initState();
    _msgSub = context.read<SessionController>().messages.listen((m) {
      if (mounted) toast(context, m);
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    super.dispose();
  }

  Future<void> _end() async {
    final controller = context.read<SessionController>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End session?'),
        content: const Text('Everyone not marked will be recorded as absent.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep going')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('End session')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // This screen is replaced once the session ends, so keep the navigator.
    final nav = Navigator.of(context);
    final summary = await withProgress(context, 'Collecting scans and syncing…', controller.end);
    if (summary != null) {
      nav.push(MaterialPageRoute(builder: (_) => SessionSummaryScreen(summary: summary)));
    }
  }

  void _manualSheet(ActiveSession s) {
    final controller = context.read<SessionController>();
    final unmarked = s.roster.where((r) => !s.marks.containsKey(r.studentId)).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        builder: (_, scroll) => Column(children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 8),
            child: Text('Mark manually', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Muted('For students whose finger is not recognised or who have no fingerprint yet.'),
          ),
          Expanded(
            child: unmarked.isEmpty
                ? const Center(child: Muted('Everyone is marked.'))
                : ListView.builder(
                    controller: scroll,
                    itemCount: unmarked.length,
                    itemBuilder: (_, i) {
                      final r = unmarked[i];
                      return ListTile(
                        title: Text(r.fullName),
                        subtitle: Text(r.regNo + (r.slot == null ? ' · no fingerprint' : '')),
                        trailing: const Icon(Icons.add_circle_outline),
                        onTap: () {
                          controller.markManually(r);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SessionController>();
    final device = context.watch<DeviceService>();
    final s = controller.active;
    if (s == null) return const SizedBox.shrink();
    final c = AppColors.of(context);
    final byId = {for (final r in s.roster) r.studentId: r};
    final feed = s.marks.values.toList()..sort((a, b) => b.at.compareTo(a.at));
    final timeFmt = DateFormat('HH:mm:ss');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live session'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(child: Tag('● Recording', kind: TagKind.ok)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          Muted('${s.course.code} · ${s.type} · started ${DateFormat('HH:mm').format(s.startedAt)} · '
              'late after ${s.lateAfterMin} min'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: StatCard(value: '${s.marks.length}', label: 'Present')),
            const SizedBox(width: 10),
            Expanded(child: StatCard(value: '${s.roster.length - s.marks.length}', label: 'Not yet')),
          ]),
          if (!device.isConnected)
            Card(
              color: c.warnSoft,
              child: ListTile(
                leading: Icon(Icons.bluetooth_disabled, color: c.warn),
                title: const Text('Device disconnected'),
                subtitle: const Text('The device keeps recording. Reconnect to collect the scans.'),
                trailing: device.connecting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : TextButton(
                        onPressed: () async {
                          try {
                            await device.reconnect();
                          } catch (_) {
                            if (context.mounted) {
                              Navigator.push(
                                  context, MaterialPageRoute(builder: (_) => const ConnectDeviceScreen()));
                            }
                          }
                        },
                        child: const Text('Reconnect'),
                      ),
              ),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                FingerprintGraphic(step: 3, size: 64),
                Muted(
                  '${s.withFingerprint} of ${s.roster.length} students loaded on the device. '
                  'Students place a finger to mark attendance.',
                  align: TextAlign.center,
                  size: 12,
                ),
                if (device.isSimulated) ...[
                  const SizedBox(height: 10),
                  FilledButton.tonal(onPressed: device.simulateFinger, child: const Text('Simulate student scan')),
                ],
              ]),
            ),
          ),
          Card(
            child: feed.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Muted('No scans yet.'))
                : Column(children: [
                    for (final m in feed.take(50))
                      ListTile(
                        dense: true,
                        title: Text(byId[m.studentId]?.fullName ?? '?',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${byId[m.studentId]?.regNo ?? ''} · ${timeFmt.format(m.at)}'
                            '${m.method == 'manual' ? ' · manual' : ''}'),
                        trailing: Tag(m.status == 'late' ? 'Late' : 'Present',
                            kind: m.status == 'late' ? TagKind.warn : TagKind.ok),
                      ),
                  ]),
          ),
          OutlinedButton(onPressed: () => _manualSheet(s), child: const Text('Mark manually')),
          const SizedBox(height: 8),
          FilledButton(onPressed: _end, child: const Text('End session and sync')),
        ],
      ),
    );
  }
}

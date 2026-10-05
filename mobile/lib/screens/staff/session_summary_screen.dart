import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/session_controller.dart';
import '../../services/sync_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class SessionSummaryScreen extends StatelessWidget {
  const SessionSummaryScreen({super.key, required this.summary});
  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncService>();
    final c = AppColors.of(context);
    final synced = sync.pending == 0;
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 24),
        children: [
          Icon(synced ? Icons.check_circle_outline : Icons.cloud_upload_outlined,
              size: 72, color: synced ? c.ok : c.warn),
          const SizedBox(height: 8),
          Text(synced ? 'Session saved' : 'Session saved on phone', textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Muted(
            synced
                ? 'Attendance synced to the database.'
                : '${sync.pending} items waiting for a connection. They upload automatically.',
            align: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(children: [
              ListTile(title: const Text('Course'), trailing: Text(summary.courseCode)),
              const Divider(),
              ListTile(title: const Text('Present'), trailing: Text('${summary.present}')),
              const Divider(),
              ListTile(title: const Text('Late'), trailing: Text('${summary.late}')),
              const Divider(),
              ListTile(title: const Text('Absent (auto-marked)'), trailing: Text('${summary.absent}')),
            ]),
          ),
          if (!synced)
            OutlinedButton(onPressed: sync.flush, child: const Text('Retry sync now')),
          const SizedBox(height: 8),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      ),
    );
  }
}

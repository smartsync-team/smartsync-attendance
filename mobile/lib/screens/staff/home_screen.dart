import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/app_state.dart';
import '../../services/device_service.dart';
import '../../services/session_controller.dart';
import '../../services/sync_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'connect_device_screen.dart';
import 'courses_screen.dart';
import 'export_screen.dart';
import 'register_flow.dart';
import 'users_screen.dart';

class StaffHomeScreen extends StatelessWidget {
  const StaffHomeScreen({super.key, required this.onGoTab});

  final ValueChanged<int> onGoTab;

  String _greeting() {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final sync = context.watch<SyncService>();
    final session = context.watch<SessionController>();
    final me = app.profile!;

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              if (session.active != null) {
                toast(context, 'End the live session before signing out.');
                return;
              }
              await app.signOut();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: app.refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          children: [
            Muted(_greeting()),
            Text(me.fullName.isEmpty ? me.email : me.fullName,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            Muted(me.isAdmin ? 'Admin' : 'Lecturer', size: 12),
            const SizedBox(height: 14),
            const _DeviceCard(),
            if (sync.pending > 0)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_upload_outlined),
                  title: Text('${sync.pending} records waiting to sync'),
                  subtitle: Text(sync.lastError == null ? 'Uploading…' : 'No connection. Retrying automatically.'),
                  trailing: TextButton(onPressed: sync.flush, child: const Text('Retry')),
                ),
              ),
            if (session.active != null)
              Card(
                child: ListTile(
                  leading: Icon(Icons.radio_button_checked, color: AppColors.of(context).ok),
                  title: Text('Live: ${session.active!.course.code}'),
                  subtitle: Text('${session.active!.marks.length} marked'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onGoTab(1),
                ),
              ),
            const SectionLabel('My courses'),
            if (app.courses.isEmpty)
              Card(
                child: ListTile(
                  title: const Text('No courses yet'),
                  subtitle: const Text('Create your first course to start taking attendance.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoursesScreen())),
                ),
              ),
            for (final c in app.courses)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(c.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                    if (c.semester != null) Muted(c.semester!),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: session.active != null
                          ? null
                          : () {
                              session.preselectedCourseId = c.id;
                              onGoTab(1);
                            },
                      child: const Text('Start attendance'),
                    ),
                  ]),
                ),
              ),
            const SectionLabel('Quick actions'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.9,
              children: [
                _QuickAction('Register student', 'QR + fingerprint', Icons.person_add_alt,
                    () => startRegisterFlow(context)),
                _QuickAction('Export report', 'Excel or CSV', Icons.file_download_outlined,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExportScreen()))),
                _QuickAction('Courses', 'Create, join QR', Icons.menu_book_outlined,
                    () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CoursesScreen()))),
                if (me.isAdmin)
                  _QuickAction('Users', 'Lecturer access', Icons.admin_panel_settings_outlined,
                      () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UsersScreen()))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard();

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DeviceService>();
    final info = d.info;
    final subtitle = !d.isConnected
        ? (d.connecting ? 'Connecting…' : 'Not connected')
        : [d.name ?? 'Device', if (info?.battery != null) 'battery ${info!.battery}%', if (info != null) 'holds ${info.capacity}']
            .join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Fingerprint device', style: TextStyle(fontWeight: FontWeight.w700)),
                Muted(subtitle),
              ]),
            ),
            d.isConnected
                ? Tag(d.isSimulated ? 'Demo' : 'Connected', kind: TagKind.ok)
                : const Tag('Offline', kind: TagKind.warn),
          ]),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConnectDeviceScreen())),
            child: Text(d.isConnected ? 'Change device' : 'Connect device'),
          ),
        ]),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(this.title, this.subtitle, this.icon, this.onTap);
  final String title, subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 20, color: AppColors.of(context).brand),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              Muted(subtitle, size: 12),
            ]),
          ),
        ),
      );
}

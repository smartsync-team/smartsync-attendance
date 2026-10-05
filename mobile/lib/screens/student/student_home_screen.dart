import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../models.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'student_shell.dart';

typedef _Data = ({List<Course> courses, List<StudentSummary> summaries, List<Map<String, dynamic>> recent});

class StudentHomeScreen extends StatefulWidget {
  const StudentHomeScreen({super.key, required this.onShowQr});
  final VoidCallback onShowQr;

  @override
  State<StudentHomeScreen> createState() => _StudentHomeScreenState();
}

class _StudentHomeScreenState extends State<StudentHomeScreen> {
  late Future<_Data> _future = _fetch();

  Future<_Data> _fetch() async {
    final id = context.read<AppState>().student!.id;
    final r = await Future.wait([Api.myStudentCourses(id), Api.myCourseSummaries(id), Api.myRecentAttendance(id)]);
    return (
      courses: r[0] as List<Course>,
      summaries: r[1] as List<StudentSummary>,
      recent: r[2] as List<Map<String, dynamic>>,
    );
  }

  Future<void> _reload() async {
    final app = context.read<AppState>();
    setState(() => _future = _fetch());
    await app.refresh();
  }

  Future<void> _join() async {
    final course = await pickCourse(context, hint: 'Scan the course QR code shown by your lecturer.');
    if (course == null || !mounted) return;
    final ok = await withProgress(context, 'Joining ${course.code}…', () async {
      await Api.joinCourse(course.id);
      return true;
    });
    if (ok == true && mounted) {
      toast(context, 'Joined ${course.code}');
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = app.student!;
    final c = AppColors.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: [IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: app.signOut)],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          children: [
            Muted(s.regNo),
            Text(s.fullName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            Card(
              color: s.hasFingerprint ? null : c.warnSoft,
              child: ListTile(
                leading: Icon(Icons.fingerprint, color: s.hasFingerprint ? c.ok : c.warn, size: 32),
                title: Text(s.hasFingerprint ? 'Fingerprint enrolled' : 'Fingerprint not enrolled yet',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(s.hasFingerprint
                    ? 'Place your finger on the device in class to mark attendance.'
                    : 'Show your QR code to your lecturer to enroll.'),
                trailing: s.hasFingerprint ? null : TextButton(onPressed: widget.onShowQr, child: const Text('My QR')),
              ),
            ),
            FutureBuilder<_Data>(
              future: _future,
              builder: (_, snap) {
                if (snap.hasError) return ErrorView(errorText(snap.error!), onRetry: _reload);
                if (!snap.hasData) {
                  return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
                }
                return _body(context, snap.data!);
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _join, icon: const Icon(Icons.qr_code_scanner), label: const Text('Join a course')),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, _Data d) {
    final byCourse = {for (final s in d.summaries) s.courseId: s};
    final fmt = DateFormat('dd MMM · HH:mm');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionLabel('My courses'),
      if (d.courses.isEmpty)
        const Card(child: Padding(padding: EdgeInsets.all(16), child: Muted('You have not joined any course yet.'))),
      for (final course in d.courses)
        Builder(builder: (_) {
          final sum = byCourse[course.id];
          final pct = sum?.percent;
          final risk = pct != null && pct < AppConfig.eligibilityThreshold;
          return Card(
            child: ListTile(
              title: Text(course.label, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(sum == null || sum.sessionsHeld == 0
                  ? 'No sessions yet'
                  : '${sum.attended} of ${sum.sessionsHeld} sessions${risk ? ' · below ${AppConfig.eligibilityThreshold.round()}%' : ''}'),
              trailing: pct == null ? null : Tag('${pct.round()}%', kind: risk ? TagKind.warn : TagKind.ok),
            ),
          );
        }),
      const SectionLabel('Recent'),
      Card(
        child: d.recent.isEmpty
            ? const Padding(padding: EdgeInsets.all(16), child: Muted('No attendance records yet.'))
            : Column(children: [
                for (final r in d.recent)
                  Builder(builder: (_) {
                    final session = r['sessions'] as Map<String, dynamic>?;
                    final course = session?['courses'] as Map<String, dynamic>?;
                    final status = r['status'] as String;
                    final when = r['checked_at'] ?? session?['started_at'];
                    return ListTile(
                      dense: true,
                      title: Text('${course?['code'] ?? ''} · ${session?['session_type'] ?? ''}'),
                      subtitle: Text(when == null ? '' : fmt.format(DateTime.parse(when).toLocal())),
                      trailing: Tag(
                        status[0].toUpperCase() + status.substring(1),
                        kind: switch (status) { 'present' => TagKind.ok, 'late' => TagKind.info, _ => TagKind.warn },
                      ),
                    );
                  }),
              ]),
      ),
    ]);
  }
}

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../config.dart';
import '../../models.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../widgets/common.dart';
import 'export_screen.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

typedef _Data = ({List<SessionStat> sessions, List<StudentSummary> students});

class _RecordsScreenState extends State<RecordsScreen> {
  String? _courseId;
  Future<_Data>? _future;

  Future<_Data> _fetch(String id) async {
    final r = await Future.wait([Api.sessionStats(id), Api.courseSummary(id)]);
    return (sessions: r[0] as List<SessionStat>, students: r[1] as List<StudentSummary>);
  }

  void _load() {
    if (_courseId != null) setState(() => _future = _fetch(_courseId!));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_courseId == null && app.courses.isNotEmpty) {
      _courseId = app.courses.first.id;
      _future = _fetch(_courseId!);
    }
    final course = app.courses.where((c) => c.id == _courseId).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Records'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('Export'),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => ExportScreen(initialCourseId: _courseId))),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _load(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
          children: [
            CourseDropdown(
              courses: app.courses,
              value: _courseId,
              onChanged: (v) {
                _courseId = v;
                _load();
              },
            ),
            const SizedBox(height: 12),
            if (_future != null)
              FutureBuilder<_Data>(
                future: _future,
                builder: (_, snap) {
                  if (snap.hasError) return ErrorView(errorText(snap.error!), onRetry: _load);
                  if (!snap.hasData) {
                    return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()));
                  }
                  return _body(context, course, snap.data!);
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Course? course, _Data d) {
    final closed = d.sessions.where((s) => s.status == 'closed').toList();
    final overall = closed.isEmpty ? null : closed.map((s) => s.ratio).reduce((a, b) => a + b) / closed.length;
    final atRisk = d.students
        .where((s) => s.percent != null && s.percent! < AppConfig.eligibilityThreshold)
        .toList()
      ..sort((a, b) => a.percent!.compareTo(b.percent!));
    final fmt = DateFormat('dd MMM · HH:mm');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: ListTile(
          title: const Text('Overall attendance', style: TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${closed.length} sessions · ${d.students.length} students'),
          trailing: Text(overall == null ? '–' : '${(overall * 100).round()}%',
              style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
        ),
      ),
      const SectionLabel('Sessions'),
      Card(
        child: d.sessions.isEmpty
            ? const Padding(padding: EdgeInsets.all(16), child: Muted('No sessions yet.'))
            : Column(children: [
                for (final s in d.sessions.take(30))
                  ListTile(
                    dense: true,
                    title: Text('${fmt.format(s.startedAt)} · ${s.type}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(s.status == 'open' ? 'Open' : '${s.late} late'),
                    trailing: Tag('${s.attended}/${s.enrolled}',
                        kind: s.status == 'open'
                            ? TagKind.info
                            : (s.ratio * 100 >= AppConfig.eligibilityThreshold ? TagKind.ok : TagKind.warn)),
                  ),
              ]),
      ),
      SectionLabel('Below ${AppConfig.eligibilityThreshold.round()}% (eligibility risk)'),
      Card(
        child: atRisk.isEmpty
            ? const Padding(padding: EdgeInsets.all(16), child: Muted('Nobody is below the threshold.'))
            : Column(children: [
                for (final s in atRisk)
                  ListTile(
                    dense: true,
                    title: Text(s.fullName),
                    subtitle: Text('${s.regNo} · ${s.attended}/${s.sessionsHeld}'),
                    trailing: Tag('${s.percent!.round()}%', kind: TagKind.warn),
                  ),
              ]),
      ),
      Card(
        child: ExpansionTile(
          shape: const Border(),
          title: const Text('All students', style: TextStyle(fontWeight: FontWeight.w700)),
          children: [
            for (final s in d.students)
              ListTile(
                dense: true,
                title: Text(s.fullName),
                subtitle: Text(s.regNo),
                trailing: Text(s.percent == null ? '–' : '${s.percent!.round()}%'),
              ),
          ],
        ),
      ),
    ]);
  }
}

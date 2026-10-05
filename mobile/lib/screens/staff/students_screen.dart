import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../widgets/common.dart';
import 'register_flow.dart';
import 'student_details_screen.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  String? _courseId;
  String _query = '';
  Future<List<StudentSummary>>? _future;

  void _load() {
    if (_courseId == null) return;
    setState(() => _future = Api.courseSummary(_courseId!));
  }

  Future<void> _open(StudentSummary s) async {
    final student = await withProgress(context, 'Loading…', () => Api.studentById(s.studentId));
    if (student == null || !mounted) return;
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => StudentDetailsScreen(existing: student, courseId: _courseId)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    if (_courseId == null && app.courses.isNotEmpty) {
      _courseId = app.courses.first.id;
      _future = Api.courseSummary(_courseId!);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Students'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Register'),
              onPressed: () async {
                await startRegisterFlow(context, courseId: _courseId);
                _load();
              },
            ),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
          child: Column(children: [
            CourseDropdown(
              courses: app.courses,
              value: _courseId,
              onChanged: (v) {
                _courseId = v;
                _load();
              },
            ),
            const SizedBox(height: 10),
            TextField(
              decoration: const InputDecoration(hintText: 'Search by name or reg. number', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 10),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<StudentSummary>>(
            future: _future,
            builder: (_, snap) {
              if (_future == null) return const SizedBox.shrink();
              if (snap.hasError) return ErrorView(errorText(snap.error!), onRetry: _load);
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final all = snap.data!;
              final list = all
                  .where((s) =>
                      _query.isEmpty ||
                      s.fullName.toLowerCase().contains(_query) ||
                      s.regNo.toLowerCase().contains(_query))
                  .toList();
              final missing = all.where((s) => !s.hasFingerprint).length;
              return RefreshIndicator(
                onRefresh: () async => _load(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  itemCount: list.length + 1,
                  separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(),
                  itemBuilder: (_, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Muted('${all.length} students · $missing without fingerprint'),
                      );
                    }
                    final s = list[i - 1];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(s.regNo),
                      trailing: s.hasFingerprint
                          ? const Tag('Enrolled', kind: TagKind.ok)
                          : const Tag('No fingerprint', kind: TagKind.warn),
                      onTap: () => _open(s),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}

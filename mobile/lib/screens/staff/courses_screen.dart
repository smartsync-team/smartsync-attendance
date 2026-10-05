import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../widgets/common.dart';

class CoursesScreen extends StatelessWidget {
  const CoursesScreen({super.key});

  Future<void> _create(BuildContext context) async {
    final code = TextEditingController();
    final name = TextEditingController();
    final semester = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New course'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: code, textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Code (e.g. EE4305)')),
            const SizedBox(height: 10),
            TextField(controller: name, textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 10),
            TextField(controller: semester, decoration: const InputDecoration(labelText: 'Semester (optional)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (code.text.trim().isEmpty || name.text.trim().isEmpty) {
      toast(context, 'Code and name are required.');
      return;
    }
    final created = await withProgress(context, 'Creating course…',
        () => Api.createCourse(code: code.text, name: name.text, semester: semester.text));
    if (created != null && context.mounted) {
      await context.read<AppState>().reloadCourses();
      if (context.mounted) toast(context, '${created.code} created');
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Courses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context),
        icon: const Icon(Icons.add),
        label: const Text('New course'),
      ),
      body: app.courses.isEmpty
          ? const Center(child: Muted('No courses yet. Tap "New course".'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 90),
              children: [
                const Muted('Show a course\'s join QR in class. Students scan it in their app to register.'),
                const SizedBox(height: 12),
                for (final c in app.courses)
                  Card(
                    child: ListTile(
                      title: Text(c.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: c.semester == null ? null : Text(c.semester!),
                      trailing: const Icon(Icons.qr_code_2),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CourseQrScreen(course: c))),
                    ),
                  ),
              ],
            ),
    );
  }
}

class CourseQrScreen extends StatelessWidget {
  const CourseQrScreen({super.key, required this.course});
  final Course course;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(course.code)),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(course.name, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Muted('Students: open the Attendance app → Join course → scan this code.', align: TextAlign.center),
            const SizedBox(height: 20),
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: QrImageView(data: QrCodes.course(course.id), size: 260, backgroundColor: Colors.white),
              ),
            ),
            const SizedBox(height: 20),
            Text('Or enter code: ${course.code}', textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
      );
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'enroll_screen.dart';

class StudentDetailsScreen extends StatefulWidget {
  const StudentDetailsScreen({super.key, this.existing, this.regNo, this.fullName, this.batch, this.courseId});

  final Student? existing;
  final String? regNo;
  final String? fullName;
  final String? batch;
  final String? courseId;

  @override
  State<StudentDetailsScreen> createState() => _StudentDetailsScreenState();
}

class _StudentDetailsScreenState extends State<StudentDetailsScreen> {
  late final _reg = TextEditingController(text: widget.existing?.regNo ?? widget.regNo ?? '');
  late final _name = TextEditingController(text: widget.existing?.fullName ?? widget.fullName ?? '');
  late final _batch = TextEditingController(text: widget.existing?.batch ?? widget.batch ?? '');
  String? _courseId;

  @override
  void initState() {
    super.initState();
    final courses = context.read<AppState>().courses;
    _courseId = widget.courseId ?? (courses.length == 1 ? courses.first.id : null);
  }

  @override
  void dispose() {
    _reg.dispose();
    _name.dispose();
    _batch.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_reg.text.trim().isEmpty || _name.text.trim().isEmpty) {
      toast(context, 'Registration number and name are required.');
      return;
    }
    final student = await withProgress(context, 'Saving student…', () async {
      final s = await Api.saveStudent(regNo: _reg.text, fullName: _name.text, batch: _batch.text);
      if (_courseId != null) await Api.addToCourse(_courseId!, s.id);
      return s;
    });
    if (student == null || !mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => EnrollScreen(student: student)));
  }

  @override
  Widget build(BuildContext context) {
    final courses = context.watch<AppState>().courses;
    final existing = widget.existing;
    return Scaffold(
      appBar: AppBar(title: const Text('Student details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          Muted(existing != null
              ? 'Step 2 of 3 · Filled from the student\'s QR. Check and edit if needed.'
              : 'Step 2 of 3 · Enter the student\'s details.'),
          const SizedBox(height: 14),
          if (existing?.hasFingerprint == true)
            Card(
              color: AppColors.of(context).warnSoft,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('This student already has a fingerprint. Continuing will replace it (re-enroll).'),
              ),
            ),
          TextField(
            controller: _reg,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Registration number', hintText: 'EG/2023/5412'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Full name'),
          ),
          const SizedBox(height: 12),
          TextField(controller: _batch, decoration: const InputDecoration(labelText: 'Batch', hintText: 'E23')),
          const SizedBox(height: 12),
          CourseDropdown(
            courses: courses,
            value: _courseId,
            label: 'Add to course (optional)',
            onChanged: (v) => setState(() => _courseId = v),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: _continue, child: const Text('Continue to fingerprint')),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../services/app_state.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'student_shell.dart';

/// First-time student registration: scan the course QR shown in class, then
/// enter registration details. After this the student shows their own QR to
/// the lecturer to enroll a fingerprint.
class StudentRegisterScreen extends StatefulWidget {
  const StudentRegisterScreen({super.key});

  @override
  State<StudentRegisterScreen> createState() => _StudentRegisterScreenState();
}

class _StudentRegisterScreenState extends State<StudentRegisterScreen> {
  Course? _course;
  final _reg = TextEditingController();
  late final _name = TextEditingController(text: context.read<AppState>().profile?.fullName ?? '');
  final _batch = TextEditingController();

  @override
  void dispose() {
    _reg.dispose();
    _name.dispose();
    _batch.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final c = await pickCourse(context, hint: 'Scan the course QR code your lecturer shows in class.');
    if (c != null) setState(() => _course = c);
  }

  Future<void> _submit() async {
    if (_reg.text.trim().isEmpty || _name.text.trim().isEmpty) {
      toast(context, 'Registration number and name are required.');
      return;
    }
    final app = context.read<AppState>();
    final id = await withProgress(
      context,
      'Registering…',
      () => Api.registerStudent(
        regNo: _reg.text,
        fullName: _name.text,
        batch: _batch.text,
        courseId: _course?.id,
      ),
    );
    if (id != null) await app.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student registration'),
        actions: [IconButton(tooltip: 'Sign out', icon: const Icon(Icons.logout), onPressed: app.signOut)],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          const Muted('Step 1 · Scan the course QR. Step 2 · Enter your details. '
              'Step 3 · Show your QR to the lecturer to enroll your fingerprint.'),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              leading: Icon(_course == null ? Icons.qr_code_scanner : Icons.check_circle, color: _course == null ? c.brand : c.ok),
              title: Text(_course?.label ?? 'Scan course QR'),
              subtitle: Text(_course == null ? 'Shown by your lecturer in class' : 'Course selected'),
              trailing: TextButton(onPressed: _scan, child: Text(_course == null ? 'Scan' : 'Change')),
            ),
          ),
          const SizedBox(height: 6),
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
          const SizedBox(height: 18),
          FilledButton(onPressed: _submit, child: const Text('Register')),
          const SizedBox(height: 8),
          const Muted('You can skip the course now and join it later from Home.', align: TextAlign.center, size: 12),
        ],
      ),
    );
  }
}

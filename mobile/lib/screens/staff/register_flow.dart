import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/api.dart';
import '../../widgets/common.dart';
import '../../widgets/qr_scan_screen.dart';
import 'student_details_screen.dart';

/// Staff registration: Step 1 scan the student's QR (from their app),
/// Step 2 confirm details, Step 3 enroll the fingerprint.
Future<void> startRegisterFlow(BuildContext context, {String? courseId}) async {
  final raw = await Navigator.push<String>(
    context,
    MaterialPageRoute(
      builder: (_) => const QrScanScreen(
        title: 'Register student',
        hint: 'Step 1 of 3 · Scan the QR on the student\'s app (My QR tab).',
        manualButton: 'Enter details manually',
      ),
    ),
  );
  if (raw == null || !context.mounted) return;

  Student? existing;
  String? regNo, name, batch;

  final studentId = QrCodes.parseStudent(raw);
  if (studentId != null) {
    existing = await withProgress<Student?>(context, 'Looking up student…', () => Api.studentById(studentId));
    if (!context.mounted) return;
    if (existing == null) {
      toast(context, 'Student not found. Check the QR code or enter details manually.');
      return;
    }
  } else if (raw.isNotEmpty) {
    // Also accept a plain JSON QR: {"reg":"EG/2023/5412","name":"K. Tharshan","batch":"E23"}
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      regNo = m['reg'] as String?;
      name = m['name'] as String?;
      batch = m['batch'] as String?;
    } catch (_) {
      regNo = raw; // treat as a bare registration number
    }
  }

  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => StudentDetailsScreen(
        existing: existing,
        regNo: regNo,
        fullName: name,
        batch: batch,
        courseId: courseId,
      ),
    ),
  );
}

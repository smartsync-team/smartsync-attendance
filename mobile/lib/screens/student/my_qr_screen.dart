import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models.dart';
import '../../services/app_state.dart';
import '../../widgets/common.dart';

/// The student's personal QR. The lecturer scans it to enroll their fingerprint.
class MyQrScreen extends StatelessWidget {
  const MyQrScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>().student!;
    return Scaffold(
      appBar: AppBar(title: const Text('My QR')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Muted('Show this to your lecturer to enroll or re-enroll your fingerprint.', align: TextAlign.center),
          const SizedBox(height: 20),
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: QrImageView(data: QrCodes.student(s.id), size: 250, backgroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 20),
          Text(s.fullName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          Text(s.regNo, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          if (s.batch != null) Muted('Batch ${s.batch}', align: TextAlign.center),
        ],
      ),
    );
  }
}

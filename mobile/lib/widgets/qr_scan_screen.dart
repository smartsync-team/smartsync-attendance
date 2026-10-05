import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../theme.dart';
import 'common.dart';

/// Full-screen QR scanner. Pops with the scanned text, or with the text typed
/// into the manual-entry box, or null if cancelled.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({
    super.key,
    required this.title,
    required this.hint,
    this.manualLabel,
    this.manualButton,
  });

  final String title;
  final String hint;

  /// When set, shows a text box (e.g. "Course code") as an alternative to scanning.
  final String? manualLabel;

  /// When set, shows a button that pops with an empty string ("enter details manually").
  final String? manualButton;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final _controller = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  final _manual = TextEditingController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    _manual.dispose();
    super.dispose();
  }

  void _finish(String value) {
    if (_done) return;
    _done = true;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          Muted(widget.hint),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(fit: StackFit.expand, children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    final raw = capture.barcodes.map((b) => b.rawValue).whereType<String>().firstOrNull;
                    if (raw != null && raw.isNotEmpty) _finish(raw);
                  },
                  errorBuilder: (context, error) => Container(
                    color: const Color(0xFF0B1020),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(20),
                    child: Text('Camera unavailable: ${error.errorCode.name}',
                        textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: .62,
                      heightFactor: .62,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFF7FA2FF), width: 3),
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          if (widget.manualLabel != null) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _manual,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: widget.manualLabel),
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) _finish(v.trim());
              },
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: () {
                if (_manual.text.trim().isNotEmpty) _finish(_manual.text.trim());
              },
              child: const Text('Continue'),
            ),
          ],
          if (widget.manualButton != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => _finish(''), child: Text(widget.manualButton!)),
          ],
          const SizedBox(height: 8),
          Icon(Icons.qr_code_scanner, color: c.muted, size: 18),
        ],
      ),
    );
  }
}

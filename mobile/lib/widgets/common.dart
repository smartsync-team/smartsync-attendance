import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models.dart';
import '../theme.dart';

enum TagKind { ok, warn, info }

class Tag extends StatelessWidget {
  const Tag(this.text, {super.key, this.kind = TagKind.info});

  final String text;
  final TagKind kind;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final (bg, fg) = switch (kind) {
      TagKind.ok => (c.okSoft, c.ok),
      TagKind.warn => (c.warnSoft, c.warn),
      TagKind.info => (c.brandSoft, c.brand),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(99)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      );
}

class Muted extends StatelessWidget {
  const Muted(this.text, {super.key, this.size = 13, this.align});
  final String text;
  final double size;
  final TextAlign? align;

  @override
  Widget build(BuildContext context) =>
      Text(text, textAlign: align, style: TextStyle(color: AppColors.of(context).muted, fontSize: size));
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            Muted(label),
          ]),
        ),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView(this.message, {super.key, this.onRetry});
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 48, color: AppColors.of(context).muted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ]),
        ),
      );
}

/// Human-readable message for any error thrown by Supabase, the device, etc.
String errorText(Object e) {
  if (e is PostgrestException) return e.message;
  if (e is AuthException) return e.message;
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}

void toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

/// Runs [task] behind a blocking progress dialog. Returns null on error (after showing it).
/// The navigator and messenger are captured up front because the calling
/// widget may be replaced while the task runs (e.g. ending a live session).
Future<T?> withProgress<T>(BuildContext context, String message, Future<T> Function() task) async {
  final nav = Navigator.of(context, rootNavigator: true);
  final messenger = ScaffoldMessenger.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 20),
          Expanded(child: Text(message)),
        ]),
      ),
    ),
  );
  try {
    final r = await task();
    nav.pop();
    return r;
  } catch (e) {
    nav.pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(errorText(e)), behavior: SnackBarBehavior.floating));
    return null;
  }
}

/// Dropdown of courses. Shows a hint when the list is empty.
class CourseDropdown extends StatelessWidget {
  const CourseDropdown({super.key, required this.courses, required this.value, required this.onChanged, this.label = 'Course'});

  final List<Course> courses;
  final String? value;
  final ValueChanged<String?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (courses.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(14),
          child: Text('No courses yet. Create one from Home → Courses.'),
        ),
      );
    }
    final v = courses.any((c) => c.id == value) ? value : null;
    return DropdownButtonFormField<String>(
      initialValue: v,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [for (final c in courses) DropdownMenuItem(value: c.id, child: Text(c.label, overflow: TextOverflow.ellipsis))],
      onChanged: onChanged,
    );
  }
}

/// Big fingerprint icon that fills in as enrollment progresses.
class FingerprintGraphic extends StatelessWidget {
  const FingerprintGraphic({super.key, required this.step, this.done = false, this.size = 120});
  final int step; // 0..3
  final bool done;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    final color = done ? c.ok : (step == 0 ? c.line : c.brand);
    return Icon(Icons.fingerprint, size: size, color: color);
  }
}

class StepBars extends StatelessWidget {
  const StepBars({super.key, required this.done, this.total = 3});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (var i = 0; i < total; i++)
        Container(
          width: 38,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(color: i < done ? c.brand : c.line, borderRadius: BorderRadius.circular(9)),
        ),
    ]);
  }
}

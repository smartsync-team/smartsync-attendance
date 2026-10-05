import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/app_state.dart';
import '../../services/export_service.dart';
import '../../widgets/common.dart';

enum _Range { all, month, last30, custom }

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, this.initialCourseId});
  final String? initialCourseId;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late String? _courseId = widget.initialCourseId;
  _Range _range = _Range.all;
  DateTimeRange? _custom;
  bool _xlsx = true;
  bool _times = false;
  bool _percent = true;

  (DateTime?, DateTime?) _dates() {
    final now = DateTime.now();
    return switch (_range) {
      _Range.all => (null, null),
      _Range.month => (DateTime(now.year, now.month), null),
      _Range.last30 => (now.subtract(const Duration(days: 30)), null),
      _Range.custom => (_custom?.start, _custom?.end.add(const Duration(days: 1))),
    };
  }

  Future<void> _export() async {
    final course = context.read<AppState>().courses.where((c) => c.id == _courseId).firstOrNull;
    if (course == null) {
      toast(context, 'Pick a course.');
      return;
    }
    final (from, to) = _dates();
    final file = await withProgress(
      context,
      'Building report…',
      () => ExportService.build(
        course: course,
        from: from,
        to: to,
        xlsx: _xlsx,
        includeTimes: _times,
        includePercent: _percent,
      ),
    );
    if (file == null || !mounted) return;
    // On phones this opens the share sheet; in a browser it downloads the file.
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(file.bytes, name: file.name, mimeType: file.mimeType)],
      fileNameOverrides: [file.name],
      subject: '${course.code} attendance',
      text: '${course.code} attendance report',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    _courseId ??= app.courses.firstOrNull?.id;
    final df = DateFormat('dd MMM yyyy');

    return Scaffold(
      appBar: AppBar(title: const Text('Export report')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          const Muted('Download attendance for a course and date range, then share or save it.'),
          const SizedBox(height: 14),
          CourseDropdown(courses: app.courses, value: _courseId, onChanged: (v) => setState(() => _courseId = v)),
          const SizedBox(height: 12),
          DropdownButtonFormField<_Range>(
            initialValue: _range,
            decoration: const InputDecoration(labelText: 'Date range'),
            items: const [
              DropdownMenuItem(value: _Range.all, child: Text('All sessions')),
              DropdownMenuItem(value: _Range.month, child: Text('This month')),
              DropdownMenuItem(value: _Range.last30, child: Text('Last 30 days')),
              DropdownMenuItem(value: _Range.custom, child: Text('Custom…')),
            ],
            onChanged: (v) async {
              if (v == _Range.custom) {
                final now = DateTime.now();
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(now.year - 2),
                  lastDate: now,
                  initialDateRange: _custom,
                );
                if (picked == null) return;
                _custom = picked;
              }
              setState(() => _range = v!);
            },
          ),
          if (_range == _Range.custom && _custom != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Muted('${df.format(_custom!.start)} – ${df.format(_custom!.end)}'),
            ),
          const SectionLabel('Format'),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: const Text('Excel (.xlsx)'), selected: _xlsx, onSelected: (_) => setState(() => _xlsx = true)),
            ChoiceChip(label: const Text('CSV'), selected: !_xlsx, onSelected: (_) => setState(() => _xlsx = false)),
          ]),
          const SectionLabel('Include'),
          Card(
            child: Column(children: [
              const ListTile(
                title: Text('Per-session present / late / absent'),
                trailing: Icon(Icons.check),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('Check-in times'),
                value: _times,
                onChanged: (v) => setState(() => _times = v),
              ),
              const Divider(),
              SwitchListTile(
                title: const Text('Attendance percentage'),
                value: _percent,
                onChanged: (v) => setState(() => _percent = v),
              ),
            ]),
          ),
          const SizedBox(height: 6),
          FilledButton(onPressed: _export, child: const Text('Export report')),
        ],
      ),
    );
  }
}

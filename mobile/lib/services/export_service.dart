import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../models.dart';
import 'api.dart';

typedef ExportFile = ({Uint8List bytes, String name, String mimeType});

/// Builds attendance reports on the phone (no server code needed).
///
/// Layout: one row per student, one column per session, cells P / L / A,
/// then totals and percentage.
class ExportService {
  static Future<ExportFile> build({
    required Course course,
    DateTime? from,
    DateTime? to,
    required bool xlsx,
    required bool includeTimes,
    required bool includePercent,
  }) async {
    final data = await Api.reportData(course.id, from, to);
    final sessions = data.sessions;
    final students = data.students
        .map((r) => (id: r['student_id'] as String, s: r['students'] as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => (a.s['reg_no'] as String).compareTo(b.s['reg_no'] as String));

    final att = <String, Map<String, dynamic>>{
      for (final a in data.attendance) '${a['session_id']}|${a['student_id']}': a,
    };

    final dateFmt = DateFormat('dd MMM yyyy HH:mm');
    final timeFmt = DateFormat('HH:mm');
    final header = <String>[
      'Reg. No',
      'Name',
      'Batch',
      for (final s in sessions)
        '${dateFmt.format(DateTime.parse(s['started_at']).toLocal())} (${s['session_type']})',
      if (includePercent) ...['Attended', 'Held', '%'],
    ];

    final rows = <List<Object>>[];
    for (final st in students) {
      var attended = 0;
      final cells = <Object>[st.s['reg_no'], st.s['full_name'], st.s['batch'] ?? ''];
      for (final s in sessions) {
        final a = att['${s['id']}|${st.id}'];
        final status = a?['status'] as String?;
        var code = switch (status) { 'present' => 'P', 'late' => 'L', 'absent' => 'A', _ => '-' };
        if (status == 'present' || status == 'late') attended++;
        if (includeTimes && a?['checked_at'] != null) {
          code = '$code ${timeFmt.format(DateTime.parse(a!['checked_at']).toLocal())}';
        }
        cells.add(code);
      }
      if (includePercent) {
        final held = sessions.length;
        cells.addAll([attended, held, held == 0 ? 0.0 : double.parse((100 * attended / held).toStringAsFixed(1))]);
      }
      rows.add(cells);
    }

    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final name = '${course.code}_attendance_$stamp.${xlsx ? 'xlsx' : 'csv'}';

    if (xlsx) {
      final excel = Excel.createExcel();
      final def = excel.getDefaultSheet() ?? 'Sheet1';
      excel.rename(def, 'Attendance');
      final sheet = excel['Attendance'];
      sheet.appendRow([TextCellValue('${course.code} · ${course.name}')]);
      sheet.appendRow([TextCellValue('P = present, L = late, A = absent, - = no record')]);
      sheet.appendRow(header.map((h) => TextCellValue(h)).toList());
      for (final r in rows) {
        sheet.appendRow(r.map<CellValue>((v) {
          if (v is int) return IntCellValue(v);
          if (v is double) return DoubleCellValue(v);
          return TextCellValue(v.toString());
        }).toList());
      }
      final bytes = excel.encode();
      if (bytes == null) throw 'Could not create the Excel file.';
      return (
        bytes: Uint8List.fromList(bytes),
        name: name,
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
    }

    final sb = StringBuffer()..writeln(header.map(_csv).join(','));
    for (final r in rows) {
      sb.writeln(r.map((v) => _csv(v.toString())).join(','));
    }
    // BOM so Excel opens UTF-8 names correctly.
    return (bytes: Uint8List.fromList(utf8.encode('﻿$sb')), name: name, mimeType: 'text/csv');
  }

  static String _csv(String v) =>
      v.contains(RegExp(r'[",\n]')) ? '"${v.replaceAll('"', '""')}"' : v;
}

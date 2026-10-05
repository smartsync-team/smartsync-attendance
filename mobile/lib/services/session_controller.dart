import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import 'api.dart';
import 'device_service.dart';
import 'sync_service.dart';

class ActiveSession {
  ActiveSession({
    required this.id,
    required this.course,
    required this.type,
    required this.startedAt,
    required this.lateAfterMin,
    required this.roster,
    Map<String, Mark>? marks,
  }) : marks = marks ?? {};

  final String id;
  final Course course;
  final String type;
  final DateTime startedAt;
  final int lateAfterMin;
  final List<RosterEntry> roster;
  final Map<String, Mark> marks; // studentId → mark

  int get withFingerprint => roster.where((r) => r.slot != null).length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'course': {'id': course.id, 'code': course.code, 'name': course.name},
        'type': type,
        'startedAt': startedAt.toIso8601String(),
        'lateAfterMin': lateAfterMin,
        'roster': roster.map((r) => r.toJson()).toList(),
        'marks': marks.values.map((m) => m.toJson()).toList(),
      };

  factory ActiveSession.fromJson(Map<String, dynamic> m) => ActiveSession(
        id: m['id'],
        course: Course.fromMap(m['course']),
        type: m['type'],
        startedAt: DateTime.parse(m['startedAt']),
        lateAfterMin: m['lateAfterMin'],
        roster: (m['roster'] as List).map((r) => RosterEntry.fromJson(r)).toList(),
        marks: {
          for (final j in m['marks'] as List) (j['studentId'] as String): Mark.fromJson(j),
        },
      );
}

typedef SessionSummary = ({String courseCode, int present, int late, int absent, int total});

/// Runs a live attendance session: loads the class onto the device, turns
/// fingerprint matches into attendance marks, and survives app restarts and
/// Bluetooth drop-outs.
class SessionController extends ChangeNotifier {
  SessionController(this.device, this.sync) {
    device.addListener(_onDeviceChanged);
  }

  static const _prefsKey = 'active_session';

  final DeviceService device;
  final SyncService sync;

  ActiveSession? active;
  String? preselectedCourseId;
  StreamSubscription<Map<String, dynamic>>? _sub;
  bool _wasConnected = false;

  final _messages = StreamController<String>.broadcast();

  /// Short messages for the UI ("K. Tharshan marked present", "Not recognised", ...).
  Stream<String> get messages => _messages.stream;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return;
    try {
      active = ActiveSession.fromJson(jsonDecode(raw));
      _listen();
      notifyListeners();
    } catch (_) {
      await prefs.remove(_prefsKey);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (active == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode(active!.toJson()));
    }
  }

  void _listen() {
    _sub?.cancel();
    _sub = device.events.listen(_onEvent);
    _wasConnected = device.isConnected;
  }

  /// Load the class onto the device and open the session.
  Future<void> start({
    required Course course,
    required String type,
    required int lateAfterMin,
    required void Function(String message, double? progress) onProgress,
  }) async {
    if (!device.isConnected) throw DeviceException('Connect the fingerprint device first.');

    onProgress('Downloading class list…', null);
    final roster = await Api.rosterWithTemplates(course.id);
    final withTpl = roster.where((r) => r.template != null).toList();
    final capacity = device.info?.capacity ?? 200;
    if (withTpl.length > capacity) {
      throw DeviceException(
          '${withTpl.length} students have fingerprints, but this sensor holds only $capacity.');
    }

    onProgress('Clearing device…', null);
    await device.request({'cmd': 'CLEAR'}, 'CLEAR_OK', timeout: const Duration(seconds: 30));

    // Sensor slots start at 1; slot numbers are only meaningful for this session.
    final entries = <RosterEntry>[];
    var slot = 1;
    for (final r in roster) {
      if (r.template == null) {
        entries.add(r.student);
        continue;
      }
      final s = slot++;
      onProgress('Loading fingerprints ${s - 1}/${withTpl.length}', (s - 1) / withTpl.length);
      await device.request({'cmd': 'LOAD', 'slot': s, 'tpl': r.template}, 'LOAD_OK',
          where: (e) => e['slot'] == s);
      entries.add(RosterEntry(
          studentId: r.student.studentId, regNo: r.student.regNo, fullName: r.student.fullName, slot: s));
    }

    onProgress('Creating session…', 1);
    final id = const Uuid().v4();
    final startedAt = DateTime.now();
    await Api.createSession(
      id: id,
      courseId: course.id,
      type: type,
      lateAfterMin: lateAfterMin,
      startedAt: startedAt,
      deviceId: device.info?.id,
    );
    await device.request({'cmd': 'VERIFY_MODE', 'session': id}, 'MODE');

    active = ActiveSession(
      id: id,
      course: course,
      type: type,
      startedAt: startedAt,
      lateAfterMin: lateAfterMin,
      roster: entries,
    );
    await _persist();
    _listen();
    notifyListeners();
  }

  void _onEvent(Map<String, dynamic> e) {
    final s = active;
    if (s == null) return;
    switch (e['evt']) {
      case 'MATCH':
        final slot = e['slot'];
        final entry = s.roster.where((r) => r.slot == slot).firstOrNull;
        if (entry == null) return;
        final ts = (e['ts'] as num?)?.toInt() ?? 0;
        // If the device clock was never set, fall back to the phone's clock.
        final at = ts > 1600000000 ? DateTime.fromMillisecondsSinceEpoch(ts * 1000) : DateTime.now();
        if (s.marks.containsKey(entry.studentId)) {
          if (e['replay'] != true) _messages.add('${entry.fullName} is already marked');
          return;
        }
        _mark(entry, at, 'fingerprint');
      case 'NO_MATCH':
        _messages.add('Fingerprint not recognised. Try again.');
    }
  }

  void markManually(RosterEntry entry) {
    if (active == null || active!.marks.containsKey(entry.studentId)) return;
    _mark(entry, DateTime.now(), 'manual');
  }

  void _mark(RosterEntry entry, DateTime at, String method) {
    final s = active!;
    final lateAt = s.startedAt.add(Duration(minutes: s.lateAfterMin));
    final status = at.isAfter(lateAt) ? 'late' : 'present';
    s.marks[entry.studentId] = Mark(studentId: entry.studentId, status: status, at: at, method: method);
    sync.enqueueAttendance({
      'session_id': s.id,
      'student_id': entry.studentId,
      'status': status,
      'checked_at': at.toUtc().toIso8601String(),
      'method': method,
      'device_id': method == 'fingerprint' ? device.info?.id : null,
    });
    _persist();
    _messages.add('${entry.fullName} marked ${status == 'late' ? 'late' : 'present'}');
    notifyListeners();
  }

  void _onDeviceChanged() {
    final now = device.isConnected;
    if (now && !_wasConnected && active != null) {
      // Device came back: put it back in verify mode and collect anything
      // it recorded while the phone was away.
      resumeOnDevice();
    }
    _wasConnected = now;
  }

  Future<void> resumeOnDevice() async {
    final s = active;
    if (s == null || !device.isConnected) return;
    try {
      await device.request({'cmd': 'VERIFY_MODE', 'session': s.id}, 'MODE');
      await device.request({'cmd': 'SYNC', 'session': s.id}, 'SYNC_DONE', timeout: const Duration(seconds: 30));
    } catch (e) {
      _messages.add('Could not resume on device: $e');
    }
  }

  Future<SessionSummary> end() async {
    final s = active!;
    if (device.isConnected) {
      try {
        await device.request({'cmd': 'SYNC', 'session': s.id}, 'SYNC_DONE', timeout: const Duration(seconds: 30));
      } catch (_) {}
      try {
        await device.send({'cmd': 'IDLE'});
      } catch (_) {}
    }
    await sync.enqueueClose(s.id, DateTime.now());

    final late = s.marks.values.where((m) => m.status == 'late').length;
    final summary = (
      courseCode: s.course.code,
      present: s.marks.length - late,
      late: late,
      absent: s.roster.length - s.marks.length,
      total: s.roster.length,
    );
    await _sub?.cancel();
    _sub = null;
    active = null;
    await _persist();
    notifyListeners();
    return summary;
  }

  @override
  void dispose() {
    device.removeListener(_onDeviceChanged);
    _sub?.cancel();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'api.dart';

/// Offline-first write queue.
///
/// Attendance marks and session closes are stored in SQLite first and pushed
/// to Supabase in order. If the lecture hall has no signal, nothing is lost:
/// the queue retries every 15 seconds until it succeeds.
///
/// In a browser (demo only) there is no SQLite, so the queue lives in memory.
class SyncService extends ChangeNotifier {
  Database? _db;
  final _memory = <Map<String, Object?>>[];
  int _memoryId = 0;
  Timer? _timer;
  bool _flushing = false;
  int pending = 0;
  String? lastError;

  Future<void> init() async {
    if (!kIsWeb) {
      _db = await openDatabase(
        p.join(await getDatabasesPath(), 'attendance_queue.db'),
        version: 1,
        onCreate: (db, _) => db.execute(
            'CREATE TABLE queue (id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT NOT NULL, payload TEXT NOT NULL)'),
      );
    }
    await _count();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (pending > 0) flush();
    });
  }

  // ---- storage (SQLite on phones, memory in the browser) ----

  Future<void> _insert(String kind, String payload) async {
    if (_db == null) {
      _memory.add({'id': ++_memoryId, 'kind': kind, 'payload': payload});
    } else {
      await _db!.insert('queue', {'kind': kind, 'payload': payload});
    }
  }

  Future<List<Map<String, Object?>>> _peek(int limit) async =>
      _db == null ? _memory.take(limit).toList() : _db!.query('queue', orderBy: 'id', limit: limit);

  Future<void> _delete(List<Object?> ids) async {
    if (_db == null) {
      _memory.removeWhere((i) => ids.contains(i['id']));
    } else {
      await _db!.delete('queue', where: 'id IN (${List.filled(ids.length, '?').join(',')})', whereArgs: ids);
    }
  }

  Future<void> _count() async {
    pending = _db == null
        ? _memory.length
        : Sqflite.firstIntValue(await _db!.rawQuery('SELECT COUNT(*) FROM queue')) ?? 0;
    notifyListeners();
  }

  // ---- public API ----

  Future<void> enqueueAttendance(Map<String, dynamic> row) => _enqueue('attendance', row);

  Future<void> enqueueClose(String sessionId, DateTime endedAt) =>
      _enqueue('close', {'id': sessionId, 'ended_at': endedAt.toIso8601String()});

  Future<void> _enqueue(String kind, Map<String, dynamic> payload) async {
    await _insert(kind, jsonEncode(payload));
    await _count();
    unawaited(flush());
  }

  /// Push queued items in order. Consecutive attendance rows go up as one batch.
  Future<bool> flush() async {
    if (_flushing) return pending == 0;
    _flushing = true;
    try {
      while (true) {
        final items = await _peek(200);
        if (items.isEmpty) break;

        if (items.first['kind'] == 'attendance') {
          final batch = items.takeWhile((i) => i['kind'] == 'attendance').toList();
          await Api.upsertAttendance(
              batch.map((i) => jsonDecode(i['payload'] as String) as Map<String, dynamic>).toList());
          await _delete(batch.map((i) => i['id']).toList());
        } else {
          final payload = jsonDecode(items.first['payload'] as String);
          await Api.closeSession(payload['id'], DateTime.parse(payload['ended_at']));
          await _delete([items.first['id']]);
        }
        await _count();
      }
      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      debugPrint('Sync failed, will retry: $e');
      return false;
    } finally {
      _flushing = false;
      await _count();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

/// BLE UUIDs — must match firmware/src/config.h.
class DeviceProtocol {
  static final service = Guid('a7e1f000-5b2c-4c8a-9d1e-0f1a2b3c4d5e');
  static final command = Guid('a7e1f001-5b2c-4c8a-9d1e-0f1a2b3c4d5e'); // app → device (write)
  static final event = Guid('a7e1f002-5b2c-4c8a-9d1e-0f1a2b3c4d5e'); // device → app (notify)
}

class DeviceInfo {
  DeviceInfo({required this.id, required this.firmware, required this.capacity, required this.stored, this.battery});

  final String id;
  final String firmware;
  final int capacity; // max templates the sensor can hold
  final int stored; // templates currently on the sensor
  final int? battery; // percent, null if not measured

  factory DeviceInfo.fromEvent(Map<String, dynamic> e) => DeviceInfo(
        id: e['id'] ?? 'unknown',
        firmware: e['fw'] ?? '?',
        capacity: (e['cap'] as num?)?.toInt() ?? 200,
        stored: (e['count'] as num?)?.toInt() ?? 0,
        battery: (e['bat'] as num?)?.toInt(),
      );
}

class DeviceException implements Exception {
  DeviceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Talks to the ESP32 fingerprint device.
///
/// Wire format (both directions): one JSON object per line, terminated by '\n'.
/// Lines may be split across several BLE packets, so bytes are buffered until
/// a newline arrives. See docs/PROTOCOL.md for every command and event.
class DeviceService extends ChangeNotifier {
  BluetoothDevice? _ble;
  BluetoothCharacteristic? _cmdChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  final _rx = <int>[];
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Future<void> _writeChain = Future.value();
  _SimulatedDevice? _sim;

  DeviceInfo? info;
  String? name;
  bool connecting = false;

  bool get isConnected => _sim != null || (_ble?.isConnected ?? false);
  bool get isSimulated => _sim != null;

  /// Every event the device sends, e.g. {"evt":"MATCH","slot":3,...}.
  Stream<Map<String, dynamic>> get events => _events.stream;

  Stream<List<ScanResult>> get scanResults => FlutterBluePlus.scanResults;
  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  /// Returns an error message, or null when Bluetooth is ready to use.
  Future<String?> prepareBluetooth() async {
    if (kIsWeb) return 'Bluetooth devices are not available in the browser. Use the demo device.';
    if (await FlutterBluePlus.isSupported == false) return 'This phone does not support Bluetooth LE.';
    if (defaultTargetPlatform == TargetPlatform.android) {
      final result = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse, // only needed on Android 11 and older
      ].request();
      if (result[Permission.bluetoothScan]?.isGranted != true ||
          result[Permission.bluetoothConnect]?.isGranted != true) {
        return 'Bluetooth permission is needed to find the fingerprint device.';
      }
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {
          return 'Please turn on Bluetooth.';
        }
      }
    } else {
      final state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);
      if (state != BluetoothAdapterState.on) return 'Please turn on Bluetooth.';
    }
    return null;
  }

  Future<void> startScan() => FlutterBluePlus.startScan(
        withServices: [DeviceProtocol.service],
        timeout: const Duration(seconds: 12),
      );

  Future<void> stopScan() => kIsWeb ? Future.value() : FlutterBluePlus.stopScan();

  Future<void> connect(ScanResult result) async {
    await disconnect();
    await stopScan();
    connecting = true;
    notifyListeners();
    final d = result.device;
    try {
      await d.connect(license: License.nonprofit, timeout: const Duration(seconds: 15));
      final services = await d.discoverServices();
      final svc = services.where((s) => s.uuid == DeviceProtocol.service).firstOrNull;
      if (svc == null) throw DeviceException('This is not an attendance device.');
      _cmdChar = svc.characteristics.firstWhere((c) => c.uuid == DeviceProtocol.command);
      final evt = svc.characteristics.firstWhere((c) => c.uuid == DeviceProtocol.event);

      _rx.clear();
      _notifySub = evt.onValueReceived.listen(_onBytes);
      d.cancelWhenDisconnected(_notifySub!);
      await evt.setNotifyValue(true);

      _ble = d;
      name = result.advertisementData.advName.isNotEmpty ? result.advertisementData.advName : d.platformName;
      _connSub = d.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) {
          _cmdChar = null;
          notifyListeners();
        }
      });
      await _handshake();
    } catch (e) {
      await d.disconnect().catchError((_) {});
      _ble = null;
      rethrow;
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  /// Reconnect to the last real device (e.g. after walking out of range).
  Future<void> reconnect() async {
    final d = _ble;
    if (d == null || _sim != null || d.isConnected) return;
    connecting = true;
    notifyListeners();
    try {
      await d.connect(license: License.nonprofit, timeout: const Duration(seconds: 15));
      final services = await d.discoverServices();
      final svc = services.firstWhere((s) => s.uuid == DeviceProtocol.service);
      _cmdChar = svc.characteristics.firstWhere((c) => c.uuid == DeviceProtocol.command);
      final evt = svc.characteristics.firstWhere((c) => c.uuid == DeviceProtocol.event);
      _rx.clear();
      _notifySub = evt.onValueReceived.listen(_onBytes);
      d.cancelWhenDisconnected(_notifySub!);
      await evt.setNotifyValue(true);
      await _handshake();
    } finally {
      connecting = false;
      notifyListeners();
    }
  }

  Future<void> useSimulator() async {
    await disconnect();
    _sim = _SimulatedDevice(_emit);
    name = 'Demo device';
    _sim!.handle({'cmd': 'INFO'});
    notifyListeners();
  }

  Future<void> disconnect() async {
    _sim = null;
    await _connSub?.cancel();
    _connSub = null;
    final d = _ble;
    _ble = null;
    _cmdChar = null;
    info = null;
    name = null;
    if (d != null) await d.disconnect().catchError((_) {});
    notifyListeners();
  }

  Future<void> _handshake() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await request({'cmd': 'SET_TIME', 'ts': now}, 'TIME_OK');
    await request({'cmd': 'INFO'}, 'INFO');
  }

  void _onBytes(List<int> data) {
    for (final b in data) {
      if (b == 0x0A) {
        final line = utf8.decode(_rx, allowMalformed: true).trim();
        _rx.clear();
        if (line.isEmpty) continue;
        try {
          final msg = jsonDecode(line);
          if (msg is Map<String, dynamic>) _emit(msg);
        } catch (_) {
          debugPrint('Device sent non-JSON line: $line');
        }
      } else {
        _rx.add(b);
      }
    }
  }

  void _emit(Map<String, dynamic> e) {
    if (e['evt'] == 'INFO') {
      info = DeviceInfo.fromEvent(e);
      notifyListeners();
    }
    _events.add(e);
  }

  /// Send a command without waiting for a reply.
  Future<void> send(Map<String, dynamic> cmd) {
    if (_sim != null) {
      _sim!.handle(cmd);
      return Future.value();
    }
    final c = _cmdChar;
    final d = _ble;
    if (c == null || d == null || !d.isConnected) {
      return Future.error(DeviceException('Fingerprint device is not connected.'));
    }
    final bytes = utf8.encode('${jsonEncode(cmd)}\n');
    final chunk = max(20, d.mtuNow - 3);
    final op = _writeChain.then((_) async {
      for (var i = 0; i < bytes.length; i += chunk) {
        await c.write(bytes.sublist(i, min(i + chunk, bytes.length)));
      }
    });
    _writeChain = op.catchError((_) {});
    return op;
  }

  /// Send a command and wait for the matching event (or an ERROR event).
  Future<Map<String, dynamic>> request(
    Map<String, dynamic> cmd,
    String expect, {
    Duration timeout = const Duration(seconds: 10),
    bool Function(Map<String, dynamic>)? where,
  }) async {
    final reply = events
        .firstWhere((e) => e['evt'] == 'ERROR' || (e['evt'] == expect && (where?.call(e) ?? true)))
        .timeout(timeout, onTimeout: () => throw DeviceException('Device did not answer "${cmd['cmd']}".'));
    try {
      await send(cmd);
    } catch (_) {
      reply.ignore();
      rethrow;
    }
    final e = await reply;
    if (e['evt'] == 'ERROR') throw DeviceException(e['msg']?.toString() ?? 'Device error');
    return e;
  }

  /// Demo device only: pretend a finger was placed on the sensor.
  void simulateFinger() => _sim?.finger();
}

/// A fake device that follows the same protocol, so the whole app can be
/// tested before the hardware is built.
class _SimulatedDevice {
  _SimulatedDevice(this._emit);

  final void Function(Map<String, dynamic>) _emit;
  final _rand = Random();
  final _loaded = <int>{};
  final _matched = <int>{};
  final _log = <Map<String, dynamic>>[];
  String _mode = 'idle';
  String? _session;
  int _enrollStep = 0;

  void _later(Map<String, dynamic> e, [int ms = 120]) =>
      Future.delayed(Duration(milliseconds: ms), () => _emit(e));

  int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  void handle(Map<String, dynamic> cmd) {
    switch (cmd['cmd']) {
      case 'SET_TIME':
        _later({'evt': 'TIME_OK'});
      case 'INFO':
        _later({'evt': 'INFO', 'id': 'SIM-01', 'fw': 'demo', 'cap': 1000, 'count': _loaded.length, 'bat': 100});
      case 'CLEAR':
        _loaded.clear();
        _later({'evt': 'CLEAR_OK'}, 300);
      case 'LOAD':
        _loaded.add(cmd['slot'] as int);
        _later({'evt': 'LOAD_OK', 'slot': cmd['slot']}, 15);
      case 'ENROLL':
        _mode = 'enroll';
        _enrollStep = 1;
        _later({'evt': 'PLACE', 'n': 1});
      case 'CANCEL' || 'IDLE':
        _mode = 'idle';
        _later({'evt': 'MODE', 'mode': 'idle'});
      case 'VERIFY_MODE':
        if (cmd['session'] != _session) _matched.clear();
        _session = cmd['session'];
        _mode = 'verify';
        _later({'evt': 'MODE', 'mode': 'verify'});
      case 'SYNC':
        final rows = _log.where((r) => r['session'] == cmd['session']).toList();
        for (final r in rows) {
          _later({'evt': 'MATCH', 'slot': r['slot'], 'score': 100, 'ts': r['ts'], 'replay': true}, 10);
        }
        _later({'evt': 'SYNC_DONE', 'count': rows.length}, 50);
      default:
        _later({'evt': 'ERROR', 'msg': 'Unknown command ${cmd['cmd']}'});
    }
  }

  void finger() {
    if (_mode == 'enroll') {
      _later({'evt': 'CAPTURE', 'n': _enrollStep}, 200);
      if (_enrollStep < 3) {
        _enrollStep++;
        _later({'evt': 'LIFT'}, 400);
        _later({'evt': 'PLACE', 'n': _enrollStep}, 900);
      } else {
        _mode = 'idle';
        final tpl = base64Encode(List.generate(512, (_) => _rand.nextInt(256)));
        _later({'evt': 'ENROLL_OK', 'tpl': tpl}, 700);
      }
    } else if (_mode == 'verify') {
      if (_loaded.isEmpty) {
        _later({'evt': 'NO_MATCH'}, 300);
        return;
      }
      final fresh = _loaded.difference(_matched).toList();
      final dup = fresh.isEmpty;
      final slot = dup ? _loaded.elementAt(_rand.nextInt(_loaded.length)) : fresh[_rand.nextInt(fresh.length)];
      _matched.add(slot);
      final ts = _now;
      if (!dup) _log.add({'session': _session, 'slot': slot, 'ts': ts});
      _later({'evt': 'MATCH', 'slot': slot, 'score': 80 + _rand.nextInt(120), 'ts': ts, 'dup': dup}, 300);
    }
  }
}

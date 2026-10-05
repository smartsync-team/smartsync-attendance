import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';

import '../../services/device_service.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

class ConnectDeviceScreen extends StatefulWidget {
  const ConnectDeviceScreen({super.key});

  @override
  State<ConnectDeviceScreen> createState() => _ConnectDeviceScreenState();
}

class _ConnectDeviceScreenState extends State<ConnectDeviceScreen> {
  String? _problem;
  late final DeviceService _device = context.read<DeviceService>();

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _device.stopScan();
    super.dispose();
  }

  Future<void> _scan() async {
    final problem = await _device.prepareBluetooth();
    if (!mounted) return;
    setState(() => _problem = problem);
    if (problem == null) {
      try {
        await _device.startScan();
      } catch (e) {
        if (mounted) setState(() => _problem = errorText(e));
      }
    }
  }

  Future<void> _connect(ScanResult r) async {
    try {
      await _device.connect(r);
      if (!mounted) return;
      toast(context, 'Connected to ${_device.name}');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, 'Could not connect: ${errorText(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DeviceService>();
    final c = AppColors.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Connect device')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
        children: [
          const Muted('Turn on the fingerprint device and keep it near your phone.'),
          const SizedBox(height: 14),
          if (d.isConnected)
            Card(
              child: ListTile(
                leading: Icon(Icons.check_circle, color: c.ok),
                title: Text(d.name ?? 'Connected'),
                subtitle: Text(d.info == null
                    ? 'Connected'
                    : 'ID ${d.info!.id} · firmware ${d.info!.firmware} · ${d.info!.stored}/${d.info!.capacity} templates'),
                trailing: TextButton(onPressed: d.disconnect, child: const Text('Disconnect')),
              ),
            ),
          if (_problem != null)
            Card(
              child: ListTile(
                leading: Icon(Icons.bluetooth_disabled, color: c.warn),
                title: Text(_problem!),
                trailing: TextButton(onPressed: _scan, child: const Text('Retry')),
              ),
            ),
          Row(children: [
            const Expanded(child: SectionLabel('Nearby devices')),
            StreamBuilder<bool>(
              stream: d.isScanning,
              initialData: false,
              builder: (_, snap) => snap.data!
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                  : TextButton(onPressed: _scan, child: const Text('Scan again')),
            ),
          ]),
          StreamBuilder<List<ScanResult>>(
            stream: d.scanResults,
            initialData: const [],
            builder: (_, snap) {
              final results = snap.data!;
              if (results.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Muted('Searching over Bluetooth LE… Devices appear here as "FP-Scanner-xx".'),
                  ),
                );
              }
              return Card(
                child: Column(children: [
                  for (final r in results)
                    ListTile(
                      leading: const Icon(Icons.fingerprint),
                      title: Text(r.advertisementData.advName.isNotEmpty
                          ? r.advertisementData.advName
                          : r.device.remoteId.str),
                      subtitle: Text('Signal ${r.rssi > -70 ? 'strong' : (r.rssi > -85 ? 'ok' : 'weak')} (${r.rssi} dBm)'),
                      trailing: d.connecting
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : FilledButton.tonal(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
                              onPressed: () => _connect(r),
                              child: const Text('Connect'),
                            ),
                    ),
                ]),
              );
            },
          ),
          const SectionLabel('No hardware yet?'),
          OutlinedButton.icon(
            icon: const Icon(Icons.science_outlined),
            label: const Text('Use demo device'),
            onPressed: () async {
              await d.useSimulator();
              if (context.mounted) Navigator.pop(context);
            },
          ),
          const SizedBox(height: 6),
          const Muted('The demo device behaves like the real one, with buttons to simulate a finger on the sensor.',
              size: 12),
        ],
      ),
    );
  }
}

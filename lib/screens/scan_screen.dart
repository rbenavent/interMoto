import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/obd_service.dart';
import 'dashboard_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final List<ScanResult> _results = [];
  bool _scanning = false;
  StreamSubscription? _scanSub;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> _startScan() async {
    setState(() {
      _results.clear();
      _scanning = true;
    });

    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      setState(() {
        for (final r in results) {
          if (!_results.any((e) => e.device.remoteId == r.device.remoteId)) {
            _results.add(r);
          }
        }
      });
    });

    await Future.delayed(const Duration(seconds: 10));
    await FlutterBluePlus.stopScan();
    setState(() => _scanning = false);
  }

  Future<void> _connect(BluetoothDevice device) async {
    final obd = ObdService();
    try {
      await obd.connect(device);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => DashboardScreen(obdService: obd)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al conectar: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('interMoto', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),
          const Text(
            'Busca el adaptador OBD-BLE\nde tu Kawasaki Versys 650',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF888888), fontSize: 15),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _scanning ? null : _startScan,
            icon: _scanning
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.bluetooth_searching),
            label: Text(_scanning ? 'Buscando...' : 'Buscar dispositivos'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00e676),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      _scanning ? '' : 'Pulsa "Buscar dispositivos"',
                      style: const TextStyle(color: Color(0xFF444444)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final r = _results[i];
                      final name = r.device.platformName.isEmpty ? 'Sin nombre' : r.device.platformName;
                      final isObd = name.toLowerCase().contains('obd') ||
                          name.toLowerCase().contains('elm') ||
                          name.toLowerCase().contains('veepeak') ||
                          name.toLowerCase().contains('obdlink');
                      return Card(
                        color: const Color(0xFF1a1a1a),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            Icons.bluetooth,
                            color: isObd ? const Color(0xFF00e676) : const Color(0xFF444444),
                          ),
                          title: Text(name, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(r.device.remoteId.toString(),
                              style: const TextStyle(color: Color(0xFF555555), fontSize: 12)),
                          trailing: Text('${r.rssi} dBm', style: const TextStyle(color: Color(0xFF666666))),
                          onTap: () => _connect(r.device),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

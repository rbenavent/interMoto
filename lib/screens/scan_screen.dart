import 'dart:async';
import 'dart:io';
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
  bool _connecting = false;
  String? _connectingId;
  StreamSubscription? _scanSub;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      _requestPermissions();
    } else {
      // En escritorio: ir directo al dashboard en modo DEMO
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => DashboardScreen(obdService: ObdService())),
        );
      });
    }
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
        _results.sort((a, b) => b.rssi.compareTo(a.rssi));
      });
    });

    await Future.delayed(const Duration(seconds: 10));
    await FlutterBluePlus.stopScan();
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() { _connecting = true; _connectingId = device.remoteId.toString(); });

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
      setState(() { _connecting = false; _connectingId = null; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al conectar: $e'),
          backgroundColor: const Color(0xFF3a0000),
        ),
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
        title: const Text(
          'interMoto',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 32),
          const Icon(Icons.motorcycle, color: Color(0xFF333333), size: 64),
          const SizedBox(height: 16),
          const Text(
            'Conecta al adaptador OBD-II BLE\nde tu Kawasaki Versys 650',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF666666), fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 28),
          ElevatedButton.icon(
            onPressed: (_scanning || _connecting) ? null : _startScan,
            icon: _scanning
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                  )
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
                      style: const TextStyle(color: Color(0xFF333333)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final r    = _results[i];
                      final name = r.device.platformName.isEmpty ? 'Sin nombre' : r.device.platformName;
                      final id   = r.device.remoteId.toString();
                      final isObd = name.toLowerCase().contains('obd') ||
                          name.toLowerCase().contains('elm') ||
                          name.toLowerCase().contains('veepeak') ||
                          name.toLowerCase().contains('obdlink') ||
                          name.toLowerCase().contains('vlink') ||
                          name.toLowerCase().contains('kw902');
                      final isConnecting = _connectingId == id;

                      return Card(
                        color: isObd ? const Color(0xFF0a1a0a) : const Color(0xFF1a1a1a),
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isObd ? const Color(0xFF00e676).withAlpha(80) : const Color(0xFF222222),
                          ),
                        ),
                        child: ListTile(
                          leading: Icon(
                            Icons.bluetooth,
                            color: isObd ? const Color(0xFF00e676) : const Color(0xFF444444),
                          ),
                          title: Text(name, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(id, style: const TextStyle(color: Color(0xFF555555), fontSize: 12)),
                          trailing: isConnecting
                              ? const SizedBox(
                                  width: 20, height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00e676)),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('${r.rssi} dBm', style: const TextStyle(color: Color(0xFF555555), fontSize: 12)),
                                    if (isObd) ...[
                                      const SizedBox(width: 8),
                                      const Icon(Icons.check_circle, color: Color(0xFF00e676), size: 16),
                                    ],
                                  ],
                                ),
                          onTap: (_connecting) ? null : () => _connect(r.device),
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

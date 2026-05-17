import 'dart:async';
import 'package:flutter/material.dart';
import '../services/obd_service.dart';

class DtcScreen extends StatefulWidget {
  final ObdService obdService;
  const DtcScreen({super.key, required this.obdService});

  @override
  State<DtcScreen> createState() => _DtcScreenState();
}

class _DtcScreenState extends State<DtcScreen> {
  List<String> _dtcs = [];
  bool _loading = false;
  bool _cleared = false;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.obdService.dtcStream.listen((dtcs) {
      if (mounted) setState(() { _dtcs = dtcs; _loading = false; });
    });
    _read();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _read() async {
    setState(() { _loading = true; _cleared = false; });
    await widget.obdService.requestDtc();
  }

  Future<void> _clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        title: const Text('Borrar códigos', style: TextStyle(color: Colors.white)),
        content: const Text(
          '¿Seguro que quieres borrar todos los códigos de error?\nEsta acción no se puede deshacer.',
          style: TextStyle(color: Color(0xFF888888)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF555555))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Borrar', style: TextStyle(color: Color(0xFFff1744))),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _loading = true);
    await widget.obdService.clearDtc();
    if (mounted) setState(() { _dtcs = []; _loading = false; _cleared = true; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Códigos de error', style: TextStyle(color: Colors.white, letterSpacing: 1)),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _read,
            tooltip: 'Releer',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF00e676)),
                SizedBox(height: 16),
                Text('Leyendo ECU...', style: TextStyle(color: Color(0xFF555555))),
              ],
            ))
          : _buildBody(),
      bottomNavigationBar: _dtcs.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: ElevatedButton.icon(
                onPressed: _clear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Borrar todos los códigos'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3a0000),
                  foregroundColor: const Color(0xFFff1744),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_cleared) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, color: Color(0xFF00e676), size: 64),
            SizedBox(height: 16),
            Text('Códigos borrados', style: TextStyle(color: Color(0xFF00e676), fontSize: 18)),
          ],
        ),
      );
    }

    if (_dtcs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, color: Color(0xFF00e676), size: 64),
            SizedBox(height: 16),
            Text('Sin códigos de error', style: TextStyle(color: Color(0xFF00e676), fontSize: 18)),
            SizedBox(height: 8),
            Text('La ECU no reporta fallos', style: TextStyle(color: Color(0xFF444444))),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _dtcs.length,
      itemBuilder: (_, i) {
        final code = _dtcs[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1a1a1a),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3a0000)),
          ),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Color(0xFFff1744), size: 28),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    code,
                    style: const TextStyle(
                      color: Color(0xFFff1744),
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _dtcPrefix(code),
                    style: const TextStyle(color: Color(0xFF666666), fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _dtcPrefix(String code) {
    if (code.isEmpty) return '';
    switch (code[0]) {
      case 'P': return 'Powertrain (motor/transmisión)';
      case 'C': return 'Chassis (frenos/suspensión)';
      case 'B': return 'Body (carrocería)';
      case 'U': return 'Network (red CAN)';
      default:  return '';
    }
  }
}

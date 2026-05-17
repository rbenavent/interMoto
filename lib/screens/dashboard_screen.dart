import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/obd_service.dart';
import '../widgets/tachometer_painter.dart';

class DashboardScreen extends StatefulWidget {
  final ObdService obdService;

  const DashboardScreen({super.key, required this.obdService});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  ObdData _data = const ObdData();
  StreamSubscription? _sub;

  // Demo animation cuando no hay datos reales aún
  late final AnimationController _demoCtrl;
  late final Animation<double> _demoRpm;
  bool _demoMode = false;
  Timer? _demoFallback;

  @override
  void initState() {
    super.initState();

    _demoCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..addListener(() {
        if (_demoMode) setState(() {});
      });

    _demoRpm = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 900.0, end: 9500.0)..chain(CurveTween(curve: Curves.easeInOut)), weight: 6),
      TweenSequenceItem(tween: Tween(begin: 9500.0, end: 900.0)..chain(CurveTween(curve: Curves.easeInOut)), weight: 3),
    ]).animate(_demoCtrl);

    // Si en 3 s no llegan datos OBD, activamos demo visual
    _demoFallback = Timer(const Duration(seconds: 3), () {
      if (_data.rpm == 0 && mounted) {
        setState(() => _demoMode = true);
        _demoCtrl.repeat();
      }
    });

    _sub = widget.obdService.dataStream.listen((d) {
      if (_demoMode) {
        _demoMode = false;
        _demoCtrl.stop();
      }
      setState(() => _data = d);
    });
  }

  @override
  void dispose() {
    _demoFallback?.cancel();
    _demoCtrl.dispose();
    _sub?.cancel();
    widget.obdService.disconnect();
    super.dispose();
  }

  double get _displayRpm => _demoMode ? _demoRpm.value : _data.rpm;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      body: SafeArea(
        child: Stack(
          children: [
            // Tacómetro central
            Positioned(
              top: size.height * 0.08,
              left: 0, right: 0,
              child: Center(
                child: SizedBox(
                  width: min(size.width * 0.90, size.height * 0.52),
                  height: min(size.width * 0.90, size.height * 0.52),
                  child: CustomPaint(
                    painter: TachometerPainter(rpm: _displayRpm, maxRpm: 10500),
                  ),
                ),
              ),
            ),

            // Velocidad debajo del tacómetro
            Positioned(
              top: size.height * 0.08 + min(size.width * 0.90, size.height * 0.52) + 8,
              left: 0, right: 0,
              child: Column(
                children: [
                  Text(
                    _demoMode ? '--' : _data.speedKmh.round().toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 80, fontWeight: FontWeight.w300, height: 1),
                  ),
                  const Text('km/h', style: TextStyle(color: Color(0xFF555555), fontSize: 18)),
                ],
              ),
            ),

            // Fila de indicadores inferiores
            Positioned(
              bottom: 24,
              left: 16, right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Gauge(
                    label: 'TEMP',
                    value: _demoMode ? '--' : '${_data.coolantTemp.round()}°',
                    color: _tempColor(_data.coolantTemp),
                    icon: Icons.thermostat,
                  ),
                  _Gauge(
                    label: 'GAS',
                    value: _demoMode ? '--' : '${_data.throttlePct.round()}%',
                    color: const Color(0xFF00b0ff),
                    icon: Icons.speed,
                  ),
                  _Gauge(
                    label: 'CARGA',
                    value: _demoMode ? '--' : '${_data.engineLoadPct.round()}%',
                    color: const Color(0xFFffc400),
                    icon: Icons.bolt,
                  ),
                ],
              ),
            ),

            // Botón desconectar (esquina superior derecha)
            Positioned(
              top: 12, right: 12,
              child: IconButton(
                icon: const Icon(Icons.bluetooth_disabled, color: Color(0xFF444444)),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Desconectar',
              ),
            ),

            // Badge DEMO
            if (_demoMode)
              Positioned(
                top: 14, left: 14,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF333333),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('DEMO', style: TextStyle(color: Color(0xFF888888), fontSize: 11, letterSpacing: 2)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _tempColor(double t) {
    if (t < 70) return const Color(0xFF00b0ff);
    if (t < 100) return const Color(0xFF00e676);
    if (t < 110) return const Color(0xFFffc400);
    return const Color(0xFFff1744);
  }
}

class _Gauge extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _Gauge({required this.label, required this.value, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Color(0xFF555555), fontSize: 11, letterSpacing: 1.5)),
        ],
      ),
    );
  }
}

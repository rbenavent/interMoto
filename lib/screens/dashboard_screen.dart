import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../services/obd_service.dart';
import '../widgets/tachometer_painter.dart';
import 'dtc_screen.dart';

class DashboardScreen extends StatefulWidget {
  final ObdService obdService;

  const DashboardScreen({super.key, required this.obdService});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with SingleTickerProviderStateMixin {
  ObdData _data = const ObdData();
  StreamSubscription? _sub;

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
    final tacho = min(size.width * 0.90, size.height * 0.50);

    return Scaffold(
      backgroundColor: const Color(0xFF0a0a0a),
      body: SafeArea(
        child: Stack(
          children: [
            // Tacómetro
            Positioned(
              top: size.height * 0.06,
              left: 0, right: 0,
              child: Center(
                child: SizedBox(
                  width: tacho, height: tacho,
                  child: CustomPaint(
                    painter: TachometerPainter(rpm: _displayRpm, maxRpm: 10500),
                  ),
                ),
              ),
            ),

            // Velocidad
            Positioned(
              top: size.height * 0.06 + tacho + 4,
              left: 0, right: 0,
              child: Column(
                children: [
                  Text(
                    _demoMode ? '--' : _data.speedKmh.round().toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 72, fontWeight: FontWeight.w300, height: 1),
                  ),
                  const Text('km/h', style: TextStyle(color: Color(0xFF555555), fontSize: 16)),
                ],
              ),
            ),

            // Indicador de marcha (arriba a la derecha del tacómetro)
            Positioned(
              top: size.height * 0.06 + tacho * 0.62,
              right: size.width * 0.05 + (size.width - tacho) / 2,
              child: _GearBadge(gear: _demoMode ? 0 : _data.gear),
            ),

            // Fila de indicadores inferiores
            Positioned(
              bottom: 16,
              left: 12, right: 12,
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
                  _Gauge(
                    label: 'BATERÍA',
                    value: _demoMode ? '--' : '${_data.batteryVoltage.toStringAsFixed(1)}V',
                    color: _voltColor(_data.batteryVoltage),
                    icon: Icons.battery_charging_full,
                  ),
                ],
              ),
            ),

            // Botón desconectar
            Positioned(
              top: 8, right: 8,
              child: IconButton(
                icon: const Icon(Icons.bluetooth_disabled, color: Color(0xFF444444)),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Desconectar',
              ),
            ),

            // Botón DTCs
            Positioned(
              top: 8, left: 8,
              child: _DtcButton(
                count: _data.dtcCount,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => DtcScreen(obdService: widget.obdService)),
                ),
              ),
            ),

            // Badge DEMO
            if (_demoMode)
              Positioned(
                top: 14, left: 56,
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
    if (t < 70)  return const Color(0xFF00b0ff);
    if (t < 100) return const Color(0xFF00e676);
    if (t < 110) return const Color(0xFFffc400);
    return const Color(0xFFff1744);
  }

  Color _voltColor(double v) {
    if (v <= 0)   return const Color(0xFF444444);
    if (v < 12.0) return const Color(0xFFff1744);
    if (v < 13.5) return const Color(0xFFffc400);
    return const Color(0xFF00e676);
  }
}

class _GearBadge extends StatelessWidget {
  final int gear;
  const _GearBadge({required this.gear});

  @override
  Widget build(BuildContext context) {
    final label = gear == 0 ? '-' : gear.toString();
    return Container(
      width: 52, height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: gear == 0 ? const Color(0xFF444444) : const Color(0xFF00e676),
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text('M', style: TextStyle(color: Color(0xFF444444), fontSize: 10, letterSpacing: 1)),
        ],
      ),
    );
  }
}

class _DtcButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _DtcButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasErrors = count > 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: hasErrors ? const Color(0xFF3a0000) : const Color(0xFF111111),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: hasErrors ? const Color(0xFFff1744) : const Color(0xFF222222)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasErrors ? Icons.error_outline : Icons.check_circle_outline,
              color: hasErrors ? const Color(0xFFff1744) : const Color(0xFF444444),
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              hasErrors ? '$count DTC' : 'DTC',
              style: TextStyle(
                color: hasErrors ? const Color(0xFFff1744) : const Color(0xFF444444),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
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
      width: 82,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF111111),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF222222)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Color(0xFF555555), fontSize: 9, letterSpacing: 1.2)),
        ],
      ),
    );
  }
}

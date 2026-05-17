import 'dart:math';
import 'package:flutter/material.dart';

class TachometerPainter extends CustomPainter {
  final double rpm;
  final double maxRpm;

  static const _startAngle = 2 * pi / 3;    // 7 en punto
  static const _sweep      = 5 * pi / 3;    // 300°

  const TachometerPainter({required this.rpm, this.maxRpm = 10500});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final radius     = min(size.width, size.height) * 0.42;
    final trackWidth = radius * 0.16;
    final midR       = radius - trackWidth / 2;
    final ratio      = (rpm / maxRpm).clamp(0.0, 1.0);

    // Fondo del arco
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: midR),
      _startAngle, _sweep, false,
      Paint()
        ..color = const Color(0xFF1a1a1a)
        ..style = PaintingStyle.stroke
        ..strokeWidth = trackWidth
        ..strokeCap = StrokeCap.butt,
    );

    // Zonas atenuadas
    _drawZone(canvas, cx, cy, midR, trackWidth * 0.80, 0, 0.57, const Color(0xFF0a2a0a));
    _drawZone(canvas, cx, cy, midR, trackWidth * 0.80, 0.57, 0.86, const Color(0xFF251a00));
    _drawZone(canvas, cx, cy, midR, trackWidth * 0.80, 0.86, 1.0,  const Color(0xFF250000));

    // Arco activo
    if (ratio > 0.001) {
      _drawZone(canvas, cx, cy, midR, trackWidth * 0.80, 0,    min(ratio, 0.57), const Color(0xFF00e676));
      if (ratio > 0.57) _drawZone(canvas, cx, cy, midR, trackWidth * 0.80, 0.57, min(ratio, 0.86), const Color(0xFFffc400));
      if (ratio > 0.86) _drawZone(canvas, cx, cy, midR, trackWidth * 0.80, 0.86, ratio,            const Color(0xFFff1744));
    }

    // Marcas de escala (0..10 para Versys 650 — redline ~10500)
    final outerEdge = radius + 2;
    for (int k = 0; k <= 10; k++) {
      final angle   = _startAngle + (k / 10) * _sweep;
      final isMajor = k % 2 == 0;
      final tickLen = isMajor ? 16.0 : 8.0;
      final cosA = cos(angle);
      final sinA = sin(angle);

      canvas.drawLine(
        Offset(cx + cosA * outerEdge, cy + sinA * outerEdge),
        Offset(cx + cosA * (outerEdge + tickLen), cy + sinA * (outerEdge + tickLen)),
        Paint()
          ..color = isMajor ? const Color(0xFFd0d0d0) : const Color(0xFF484848)
          ..strokeWidth = isMajor ? 2.5 : 1.5
          ..strokeCap = StrokeCap.round,
      );

      if (isMajor) {
        final labelR = outerEdge + tickLen + 18;
        final tp = TextPainter(
          text: TextSpan(
            text: k.toString(),
            style: const TextStyle(color: Color(0xFF909090), fontSize: 20, fontWeight: FontWeight.bold),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(cx + cosA * labelR - tp.width / 2, cy + sinA * labelR - tp.height / 2));
      }
    }

    // RPM numérico central
    final rpmText = TextPainter(
      text: TextSpan(
        text: rpm.round().toString(),
        style: const TextStyle(color: Colors.white, fontSize: 72, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    rpmText.paint(canvas, Offset(cx - rpmText.width / 2, cy - rpmText.height / 2 - 14));

    final label = TextPainter(
      text: const TextSpan(
        text: 'r/min',
        style: TextStyle(color: Color(0xFF505050), fontSize: 18),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(cx - label.width / 2, cy + rpmText.height / 2 + 2));

    // Punto central
    canvas.drawCircle(Offset(cx, cy + 10), 6, Paint()..color = const Color(0xFFcc3300));
  }

  void _drawZone(Canvas canvas, double cx, double cy, double r, double w,
      double startFrac, double endFrac, Color color) {
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, cy), radius: r),
      _startAngle + startFrac * _sweep,
      (endFrac - startFrac) * _sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.butt,
    );
  }

  @override
  bool shouldRepaint(TachometerPainter old) => old.rpm != rpm;
}

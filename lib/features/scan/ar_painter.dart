import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../models/detection_result.dart';

// Цвет по типу реального дефекта (метки из детекторов)
Color _defectColor(String label) {
  final l = label.toLowerCase();
  if (l.contains('волос') || l.contains('нить') || l.contains('шерст')) {
    return const Color(0xFFFFB800);
  }
  if (l.contains('загрязн') || l.contains('пыль') || l.contains('пятно') ||
      l.contains('органик') || l.contains('тара')) {
    return const Color(0xFFFF9500);
  }
  if (l.contains('опасн') || l.contains('инструмент')) {
    return const Color(0xFFFF6B35);
  }
  if (l.contains('электрон')) return const Color(0xFF9B59B6);
  return const Color(0xFFFF3355);
}

String _defectIcon(String label) {
  final l = label.toLowerCase();
  if (l.contains('волос') || l.contains('нить')) return '╱';
  if (l.contains('загрязн') || l.contains('пыль') || l.contains('пятно')) return '✦';
  if (l.contains('опасн')) return '⚡';
  if (l.contains('электрон')) return '▣';
  return '!';
}

class ArPainter extends CustomPainter {
  final DetectionResult detection;
  final double pulse; // 0..1 animation value

  ArPainter({required this.detection, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    if (detection.isDefect) {
      _paintDefect(canvas, size);
    } else {
      _paintOk(canvas, size);
    }
  }

  void _paintOk(Canvas canvas, Size size) {
    const inset = 20.0;
    const cornerLen = 40.0;
    final paint = Paint()
      ..color = AppPalette.okGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final l = inset, t = inset;
    final r = size.width - inset, b = size.height - inset;

    canvas.drawLine(Offset(l, t), Offset(l + cornerLen, t), paint);
    canvas.drawLine(Offset(l, t), Offset(l, t + cornerLen), paint);
    canvas.drawLine(Offset(r, t), Offset(r - cornerLen, t), paint);
    canvas.drawLine(Offset(r, t), Offset(r, t + cornerLen), paint);
    canvas.drawLine(Offset(l, b), Offset(l + cornerLen, b), paint);
    canvas.drawLine(Offset(l, b), Offset(l, b - cornerLen), paint);
    canvas.drawLine(Offset(r, b), Offset(r - cornerLen, b), paint);
    canvas.drawLine(Offset(r, b), Offset(r, b - cornerLen), paint);

    _drawStatusBadge(canvas, 'ГОДНО', AppPalette.okGreen, const Offset(20, 20));

    if (detection.ssimScore != null) {
      _drawSsimHint(canvas, size);
    }
  }

  void _paintDefect(Canvas canvas, Size size) {
    final pulseAlpha = 0.65 + 0.35 * pulse;

    for (final o in detection.objects) {
      final defColor = _defectColor(o.label);
      final strokeColor = defColor.withOpacity(pulseAlpha);
      final fillColor = defColor.withOpacity(0.10 + 0.08 * pulse);

      final stroke = Paint()
        ..color = strokeColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      final fill = Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill;

      final rect = Rect.fromLTWH(
        o.bbox.left * size.width,
        o.bbox.top * size.height,
        o.bbox.width * size.width,
        o.bbox.height * size.height,
      );
      final rr = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, stroke);

      // Уголки рамки
      _drawCorners(canvas, rect, defColor, pulseAlpha);

      // Иконка типа дефекта в центре bbox
      final icon = _defectIcon(o.label);
      final iconTp = _text(icon, color: defColor.withOpacity(0.7), size: 28, weight: FontWeight.w900);
      iconTp.paint(
        canvas,
        Offset(
          rect.center.dx - iconTp.width / 2,
          rect.center.dy - iconTp.height / 2,
        ),
      );

      // Метка с типом и уверенностью — ниже bbox если нет места сверху
      final labelText = '${o.label}  ${(o.confidence * 100).toInt()}%';
      final labelY = rect.top >= 28 ? rect.top - 26 : rect.bottom + 4;
      _drawLabel(canvas, labelText, Offset(rect.left, labelY), defColor);
    }

    _drawStatusBadge(canvas, 'БРАК', AppPalette.defectRed, const Offset(20, 20));

    if (detection.ssimScore != null) {
      _drawSsimHint(canvas, size);
    }
  }

  void _drawCorners(Canvas canvas, Rect r, Color color, double alpha) {
    const len = 16.0;
    final p = Paint()
      ..color = color.withOpacity(alpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(r.left, r.top), Offset(r.left + len, r.top), p);
    canvas.drawLine(Offset(r.left, r.top), Offset(r.left, r.top + len), p);
    canvas.drawLine(Offset(r.right, r.top), Offset(r.right - len, r.top), p);
    canvas.drawLine(Offset(r.right, r.top), Offset(r.right, r.top + len), p);
    canvas.drawLine(Offset(r.left, r.bottom), Offset(r.left + len, r.bottom), p);
    canvas.drawLine(Offset(r.left, r.bottom), Offset(r.left, r.bottom - len), p);
    canvas.drawLine(Offset(r.right, r.bottom), Offset(r.right - len, r.bottom), p);
    canvas.drawLine(Offset(r.right, r.bottom), Offset(r.right, r.bottom - len), p);
  }

  void _drawStatusBadge(Canvas canvas, String text, Color color, Offset pos) {
    final tp = _text(text, color: Colors.white, size: 13, weight: FontWeight.w600);
    const pad = EdgeInsets.symmetric(horizontal: 12, vertical: 6);
    final rect = Rect.fromLTWH(
      pos.dx,
      pos.dy,
      tp.width + pad.horizontal,
      tp.height + pad.vertical,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(999)),
      Paint()..color = color,
    );
    tp.paint(canvas, Offset(rect.left + pad.left, rect.top + pad.top));
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, Color bgColor) {
    final tp = _text(text, color: Colors.white, size: 12, weight: FontWeight.w600);
    final rect = Rect.fromLTWH(pos.dx, pos.dy, tp.width + 12, tp.height + 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = bgColor,
    );
    tp.paint(canvas, Offset(pos.dx + 6, pos.dy + 3));
  }

  void _drawSsimHint(Canvas canvas, Size size) {
    final s = detection.ssimScore!;
    final tp = _text('SSIM ${s.toStringAsFixed(2)}',
        color: Colors.white.withOpacity(0.85), size: 11, weight: FontWeight.w500);
    final pos = Offset(size.width - tp.width - 20, size.height - tp.height - 18);
    tp.paint(canvas, pos);
  }

  TextPainter _text(String s,
      {required Color color, required double size, required FontWeight weight}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(color: color, fontSize: size, fontWeight: weight),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  }

  @override
  bool shouldRepaint(covariant ArPainter old) =>
      old.detection != detection || old.pulse != pulse;
}

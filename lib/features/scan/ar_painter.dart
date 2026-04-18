import 'package:flutter/material.dart';
import '../../core/constants.dart';
import '../../models/detection_result.dart';

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

    // four corners
    canvas.drawLine(Offset(l, t), Offset(l + cornerLen, t), paint);
    canvas.drawLine(Offset(l, t), Offset(l, t + cornerLen), paint);
    canvas.drawLine(Offset(r, t), Offset(r - cornerLen, t), paint);
    canvas.drawLine(Offset(r, t), Offset(r, t + cornerLen), paint);
    canvas.drawLine(Offset(l, b), Offset(l + cornerLen, b), paint);
    canvas.drawLine(Offset(l, b), Offset(l, b - cornerLen), paint);
    canvas.drawLine(Offset(r, b), Offset(r - cornerLen, b), paint);
    canvas.drawLine(Offset(r, b), Offset(r, b - cornerLen), paint);

    _drawStatusBadge(
      canvas,
      'ГОДНО',
      AppPalette.okGreen,
      const Offset(20, 20),
    );

    if (detection.ssimScore != null) {
      _drawSsimHint(canvas, size);
    }
  }

  void _paintDefect(Canvas canvas, Size size) {
    final pulseAlpha = 0.65 + 0.35 * pulse;
    final strokeColor = AppPalette.defectRed.withOpacity(pulseAlpha);
    final fillColor = AppPalette.defectRed.withOpacity(0.08 + 0.08 * pulse);

    final stroke = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final fill = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    for (final o in detection.objects) {
      final r = Rect.fromLTWH(
        o.bbox.left * size.width,
        o.bbox.top * size.height,
        o.bbox.width * size.width,
        o.bbox.height * size.height,
      );
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(6));
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, stroke);
      _drawLabel(canvas, '${o.label} ${(o.confidence * 100).toInt()}%',
          Offset(r.left, r.top - 24));
    }

    _drawStatusBadge(
      canvas,
      'БРАК',
      AppPalette.defectRed,
      const Offset(20, 20),
    );

    if (detection.ssimScore != null) {
      _drawSsimHint(canvas, size);
    }
  }

  void _drawStatusBadge(Canvas canvas, String text, Color color, Offset pos) {
    final tp = _text(text,
        color: Colors.white, size: 13, weight: FontWeight.w600);
    final pad = const EdgeInsets.symmetric(horizontal: 12, vertical: 6);
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

  void _drawLabel(Canvas canvas, String text, Offset pos) {
    final tp = _text(text,
        color: Colors.white, size: 12, weight: FontWeight.w600);
    final rect = Rect.fromLTWH(pos.dx, pos.dy, tp.width + 12, tp.height + 6);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = AppPalette.defectRed,
    );
    tp.paint(canvas, Offset(pos.dx + 6, pos.dy + 3));
  }

  void _drawSsimHint(Canvas canvas, Size size) {
    final s = detection.ssimScore!;
    final tp = _text('SSIM ${s.toStringAsFixed(2)}',
        color: Colors.white.withOpacity(0.85),
        size: 11,
        weight: FontWeight.w500);
    final pos = Offset(size.width - tp.width - 20, size.height - tp.height - 18);
    tp.paint(canvas, pos);
  }

  TextPainter _text(String s,
      {required Color color,
      required double size,
      required FontWeight weight}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: weight,
          fontFamily: 'JetBrainsMono',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  }

  @override
  bool shouldRepaint(covariant ArPainter old) =>
      old.detection != detection || old.pulse != pulse;
}

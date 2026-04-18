import 'package:flutter/material.dart';

class DetectionObject {
  final String label;
  final double confidence;
  final Rect bbox; // normalized [0,1]

  const DetectionObject({
    required this.label,
    required this.confidence,
    required this.bbox,
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'confidence': confidence,
        'x': bbox.left,
        'y': bbox.top,
        'w': bbox.width,
        'h': bbox.height,
      };

  factory DetectionObject.fromJson(Map<String, dynamic> j) => DetectionObject(
        label: j['label'] as String,
        confidence: (j['confidence'] as num).toDouble(),
        bbox: Rect.fromLTWH(
          (j['x'] as num).toDouble(),
          (j['y'] as num).toDouble(),
          (j['w'] as num).toDouble(),
          (j['h'] as num).toDouble(),
        ),
      );
}

class DetectionResult {
  final bool isDefect;
  final String result; // "OK" | "DEFECT"
  final List<DetectionObject> objects;
  final double? ssimScore;
  final bool? isAnomaly;
  final DateTime timestamp;

  const DetectionResult({
    required this.isDefect,
    required this.result,
    required this.objects,
    this.ssimScore,
    this.isAnomaly,
    required this.timestamp,
  });

  factory DetectionResult.ok({double? ssim, bool? anomaly}) => DetectionResult(
        isDefect: false,
        result: 'OK',
        objects: const [],
        ssimScore: ssim,
        isAnomaly: anomaly,
        timestamp: DateTime.now(),
      );

  factory DetectionResult.empty() => DetectionResult(
        isDefect: false,
        result: 'OK',
        objects: const [],
        timestamp: DateTime.now(),
      );

  String get defectType => objects.isNotEmpty
      ? objects.first.label
      : (isAnomaly == true ? 'anomaly' : 'none');

  double get topConfidence =>
      objects.isNotEmpty ? objects.first.confidence : 0.0;
}

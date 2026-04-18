import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../core/constants.dart';
import '../models/detection_result.dart';
import 'detector_service.dart';
import 'detector_web_stub.dart' if (dart.library.html) 'detector_web_impl.dart'
    as web;

class DetectorWeb implements DetectorService {
  List<String> _labels = const [];
  bool _ready = false;

  @override
  Future<void> initialize() async {
    try {
      final raw = await rootBundle.loadString(AppConstants.labelsPath);
      _labels = raw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    } catch (e) {
      debugPrint('[DetectorWeb] labels load failed: $e');
    }
    // Always try to load YOLO, but don't block on failure —
    // JS side has its own contamination detector that works without YOLO.
    try {
      await web.webLoadModel(AppConstants.modelWebPath);
    } catch (e) {
      debugPrint('[DetectorWeb] YOLO model not loaded (OK, using JS fallback): $e');
    }
    _ready = true; // Always ready — JS contamination detector is standalone
  }

  @override
  Future<DetectionResult> detect(dynamic frame) async {
    if (!_ready) return DetectionResult.empty();
    try {
      final raw = await web.webDetect(frame);
      final list = (jsonDecode(raw) as List)
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final objs = <DetectionObject>[];
      for (final o in list) {
        final cls = (o['classIndex'] as num).toInt();
        final conf = (o['confidence'] as num).toDouble();
        if (conf < AppConstants.confidenceThreshold) continue;
        final cw = (o['canvasWidth'] as num?)?.toDouble() ?? 1.0;
        final ch = (o['canvasHeight'] as num?)?.toDouble() ?? 1.0;
        final x1 = (o['x1'] as num).toDouble() / cw;
        final y1 = (o['y1'] as num).toDouble() / ch;
        final x2 = (o['x2'] as num).toDouble() / cw;
        final y2 = (o['y2'] as num).toDouble() / ch;
        final label = cls < _labels.length ? _labels[cls] : 'obj$cls';
        objs.add(DetectionObject(
          label: label,
          confidence: conf,
          bbox: Rect.fromLTWH(x1, y1, x2 - x1, y2 - y1),
        ));
      }
      final isDefect = objs.isNotEmpty;
      return DetectionResult(
        isDefect: isDefect,
        result: isDefect ? 'DEFECT' : 'OK',
        objects: objs,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[DetectorWeb] detect err: $e');
      return DetectionResult.empty();
    }
  }

  @override
  Future<void> dispose() async {
    _ready = false;
  }
}

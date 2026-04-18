import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../core/constants.dart';
import '../models/detection_result.dart';
import 'detector_service.dart';

class DetectorMobile implements DetectorService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  bool _modelReady = false;

  @override
  Future<void> initialize() async {
    try {
      final options = InterpreterOptions()..threads = 4;
      _interpreter = await Interpreter.fromAsset(
        AppConstants.modelTflitePath,
        options: options,
      );
      final labelsRaw = await rootBundle.loadString(AppConstants.labelsPath);
      _labels = labelsRaw
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      _modelReady = true;
      debugPrint('[Detector] TFLite ready, labels: ${_labels.length}');
    } catch (e) {
      debugPrint('[Detector] model missing, running in stub mode: $e');
      _modelReady = false;
    }
  }

  @override
  Future<DetectionResult> detect(dynamic frame) async {
    if (!_modelReady || frame is! CameraImage) {
      return DetectionResult.empty();
    }
    try {
      final rgb = _cameraImageToRgb(frame);
      if (rgb == null) return DetectionResult.empty();
      final resized = img.copyResize(
        rgb,
        width: AppConstants.inputSize,
        height: AppConstants.inputSize,
      );
      final input = _toInputTensor(resized);
      final output = List.generate(
        1,
        (_) => List.generate(84, (_) => List.filled(8400, 0.0)),
      );
      _interpreter!.run(input, output);
      final objs = _parseYolov8(output[0]);
      final filtered = _nms(objs, AppConstants.iouThreshold);
      final isDefect = filtered.isNotEmpty;
      return DetectionResult(
        isDefect: isDefect,
        result: isDefect ? 'DEFECT' : 'OK',
        objects: filtered,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      debugPrint('[Detector] inference error: $e');
      return DetectionResult.empty();
    }
  }

  img.Image? _cameraImageToRgb(CameraImage ci) {
    try {
      if (ci.format.group == ImageFormatGroup.yuv420) {
        return _yuv420ToImage(ci);
      } else if (ci.format.group == ImageFormatGroup.bgra8888) {
        return img.Image.fromBytes(
          width: ci.width,
          height: ci.height,
          bytes: ci.planes[0].bytes.buffer,
          order: img.ChannelOrder.bgra,
        );
      }
    } catch (_) {}
    return null;
  }

  img.Image _yuv420ToImage(CameraImage ci) {
    final w = ci.width, h = ci.height;
    final out = img.Image(width: w, height: h);
    final yPlane = ci.planes[0];
    final uPlane = ci.planes[1];
    final vPlane = ci.planes[2];
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel ?? 1;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final yIndex = y * yPlane.bytesPerRow + x;
        final uvIndex = (y >> 1) * uvRowStride + (x >> 1) * uvPixelStride;
        final yp = yPlane.bytes[yIndex] & 0xff;
        final up = uPlane.bytes[uvIndex] & 0xff;
        final vp = vPlane.bytes[uvIndex] & 0xff;
        int r = (yp + 1.402 * (vp - 128)).round();
        int g = (yp - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).round();
        int b = (yp + 1.772 * (up - 128)).round();
        r = r.clamp(0, 255);
        g = g.clamp(0, 255);
        b = b.clamp(0, 255);
        out.setPixelRgb(x, y, r, g, b);
      }
    }
    return out;
  }

  List<List<List<List<double>>>> _toInputTensor(img.Image image) {
    final size = AppConstants.inputSize;
    final tensor = List.generate(
      1,
      (_) => List.generate(
        size,
        (_) => List.generate(size, (_) => List.filled(3, 0.0)),
      ),
    );
    for (int y = 0; y < size; y++) {
      for (int x = 0; x < size; x++) {
        final px = image.getPixel(x, y);
        tensor[0][y][x][0] = px.r / 255.0;
        tensor[0][y][x][1] = px.g / 255.0;
        tensor[0][y][x][2] = px.b / 255.0;
      }
    }
    return tensor;
  }

  List<DetectionObject> _parseYolov8(List<List<double>> output) {
    // output shape: [84, 8400] — 4 bbox + 80 class scores
    const numBoxes = 8400;
    const numClasses = 80;
    final results = <DetectionObject>[];
    for (int i = 0; i < numBoxes; i++) {
      double best = 0;
      int bestC = 0;
      for (int c = 0; c < numClasses; c++) {
        final s = output[4 + c][i];
        if (s > best) {
          best = s;
          bestC = c;
        }
      }
      if (best < AppConstants.confidenceThreshold) continue;
      final cx = output[0][i] / AppConstants.inputSize;
      final cy = output[1][i] / AppConstants.inputSize;
      final w = output[2][i] / AppConstants.inputSize;
      final h = output[3][i] / AppConstants.inputSize;
      final rect = Rect.fromLTWH(cx - w / 2, cy - h / 2, w, h);
      final rawLabel = bestC < _labels.length ? _labels[bestC] : 'obj$bestC';
      results.add(DetectionObject(
        label: rawLabel,
        confidence: best,
        bbox: rect,
      ));
    }
    return results;
  }

  List<DetectionObject> _nms(List<DetectionObject> objs, double iouThr) {
    objs.sort((a, b) => b.confidence.compareTo(a.confidence));
    final kept = <DetectionObject>[];
    for (final o in objs) {
      bool drop = false;
      for (final k in kept) {
        if (_iou(o.bbox, k.bbox) > iouThr) {
          drop = true;
          break;
        }
      }
      if (!drop) kept.add(o);
      if (kept.length >= 20) break;
    }
    return kept;
  }

  double _iou(Rect a, Rect b) {
    final x1 = math.max(a.left, b.left);
    final y1 = math.max(a.top, b.top);
    final x2 = math.min(a.right, b.right);
    final y2 = math.min(a.bottom, b.bottom);
    final inter = math.max(0, x2 - x1) * math.max(0, y2 - y1);
    final ua = a.width * a.height + b.width * b.height - inter;
    return ua <= 0 ? 0 : inter / ua;
  }

  @override
  Future<void> dispose() async {
    _interpreter?.close();
    _interpreter = null;
    _modelReady = false;
  }
}


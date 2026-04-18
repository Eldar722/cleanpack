import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/detection_result.dart';
// Conditional import: on Web, `dart.library.io` is absent, so the stub is
// used — this keeps `tflite_flutter` / `dart:ffi` out of the Web build graph.
import 'detector_mobile_stub.dart'
    if (dart.library.io) 'detector_mobile.dart';
import 'detector_web.dart';

/// Abstract detector. Accepts an opaque frame payload.
/// On mobile that is a `CameraImage`. On web it is an `html.VideoElement`
/// (wrapped as dynamic so this file doesn't pull in dart:html on mobile).
abstract class DetectorService {
  Future<void> initialize();
  Future<DetectionResult> detect(dynamic frame);
  Future<void> dispose();

  static DetectorService create() {
    if (kIsWeb) return DetectorWeb();
    return DetectorMobile();
  }
}

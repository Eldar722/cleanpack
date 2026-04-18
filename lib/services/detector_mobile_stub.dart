import '../models/detection_result.dart';
import 'detector_service.dart';

/// Web-compilation stub for [DetectorMobile].
///
/// Pulled in by the conditional import in `detector_service.dart` whenever
/// `dart.library.io` is absent (i.e. Flutter Web). Keeps `tflite_flutter`
/// (and therefore `dart:ffi`) out of the Web build graph.
///
/// The factory in [DetectorService.create] returns [DetectorWeb] on Web, so
/// these methods are never reached at runtime — they exist only to satisfy
/// the static type system.
class DetectorMobile implements DetectorService {
  @override
  Future<void> initialize() async {
    throw UnsupportedError(
      'DetectorMobile is not available on Web. Use DetectorWeb instead.',
    );
  }

  @override
  Future<DetectionResult> detect(dynamic frame) async {
    throw UnsupportedError(
      'DetectorMobile.detect is not available on Web.',
    );
  }

  @override
  Future<void> dispose() async {}
}

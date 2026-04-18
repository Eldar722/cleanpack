import 'dart:async';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';
import '../../core/constants.dart';
import '../../core/platform_utils.dart';
import '../../models/detection_result.dart';
import '../../models/inspection_log.dart';
import '../../services/camera_service.dart';
import '../../services/detector_service.dart';
import '../../services/pixel_anomaly_detector.dart';
import '../../services/ssim_service.dart';
import '../../services/storage_service.dart';

final logUpdateCounterProvider = StateProvider<int>((ref) => 0);

final cameraServiceProvider = Provider<CameraService>((ref) {
  final s = CameraService();
  ref.onDispose(() => s.dispose());
  return s;
});

final detectorServiceProvider = Provider<DetectorService>((ref) {
  final s = DetectorService.create();
  ref.onDispose(() => s.dispose());
  return s;
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService.create();
});

class ScanState {
  final bool initializing;
  final bool ready;
  final bool paused;
  final DetectionResult detection;
  final int fps;
  final String? error;
  final String? cameraError;

  const ScanState({
    this.initializing = true,
    this.ready = false,
    this.paused = false,
    required this.detection,
    this.fps = 0,
    this.error,
    this.cameraError,
  });

  factory ScanState.initial() => ScanState(detection: DetectionResult.empty());

  ScanState copyWith({
    bool? initializing,
    bool? ready,
    bool? paused,
    DetectionResult? detection,
    int? fps,
    String? error,
    String? cameraError,
  }) =>
      ScanState(
        initializing: initializing ?? this.initializing,
        ready: ready ?? this.ready,
        paused: paused ?? this.paused,
        detection: detection ?? this.detection,
        fps: fps ?? this.fps,
        error: error,
        cameraError: cameraError ?? this.cameraError,
      );
}

class ScanController extends StateNotifier<ScanState> {
  final Ref ref;
  Timer? _webLoop;
  Timer? _fpsTimer;
  int _frameCounter = 0;
  bool _inferring = false;
  final _uuid = const Uuid();

  // Pixel anomaly (luminance-based, no ML model required)
  final _pixelDetector = PixelAnomalyDetector();

  // SSIM
  final _ssimSvc = SsimService();
  img.Image? _referenceFrame;
  double? _lastSsimScore;
  int _ssimFrameCounter = 0;
  static const _kSsimEvery = 10; // run SSIM every N camera frames (~3/s at 30fps)

  // Defect hold — keep red frame visible for this duration after last detection
  DateTime? _lastDefectAt;
  DetectionResult? _lastDefectResult;
  static const _kDefectHold = Duration(seconds: 3);

  ScanController(this.ref) : super(ScanState.initial());

  Future<void> initialize() async {
    try {
      final det = ref.read(detectorServiceProvider);
      final store = ref.read(storageServiceProvider);
      await Future.wait([det.initialize(), store.initialize()]);

      // Load first reference image for SSIM comparison
      try {
        final refs = await store.getReferences();
        if (refs.isNotEmpty && refs.first.bytes.isNotEmpty) {
          _referenceFrame = _ssimSvc.decodePng(refs.first.bytes);
        }
      } catch (_) {}

      final cam = ref.read(cameraServiceProvider);
      String? camError;
      try {
        await cam.initialize();
        if (!cam.isInitialized) {
          camError =
              'Камера недоступна.\n${PlatformUtils.isWeb ? "В браузере нужен HTTPS или localhost.\nЗапустите сервер на localhost:8000" : "Проверьте разрешение камеры в настройках."}';
        } else {
          if (PlatformUtils.isWeb) {
            _startWebLoop();
          } else {
            await cam.startStream(_onFrame);
          }
        }
      } catch (e) {
        camError =
            'Ошибка камеры: $e\n${PlatformUtils.isWeb ? "Нужен HTTPS или localhost для getUserMedia" : ""}';
      }

      _startFpsTimer();
      state = state.copyWith(
        initializing: false,
        ready: true,
        cameraError: camError,
      );
    } catch (e) {
      state = state.copyWith(initializing: false, ready: false, error: '$e');
    }
  }

  /// Call after saving a new reference so SSIM uses the latest image.
  Future<void> reloadReference() async {
    try {
      final store = ref.read(storageServiceProvider);
      final refs = await store.getReferences();
      if (refs.isNotEmpty && refs.first.bytes.isNotEmpty) {
        _referenceFrame = _ssimSvc.decodePng(refs.first.bytes);
      } else {
        _referenceFrame = null;
      }
    } catch (_) {}
  }

  void pauseResume() {
    state = state.copyWith(paused: !state.paused);
  }

  void _startFpsTimer() {
    _fpsTimer?.cancel();
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(fps: _frameCounter);
      _frameCounter = 0;
    });
  }

  void _startWebLoop() {
    _webLoop?.cancel();
    _webLoop = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (state.paused || _inferring) return;
      _onFrame(null);
    });
  }

  Future<void> _onFrame(dynamic frame) async {
    if (state.paused) return;
    if (_inferring) return;
    _inferring = true;
    try {
      final det = ref.read(detectorServiceProvider);
      final result = await det.detect(frame);
      _frameCounter++;
      _ssimFrameCounter++;

      // Pixel anomaly: runs on mobile only (needs CameraImage YUV420)
      List<DetectionObject> pixelObjects = const [];
      if (!PlatformUtils.isWeb && frame is CameraImage) {
        pixelObjects = _pixelDetector.detect(frame);
      }

      // SSIM: run every _kSsimEvery frames on mobile only (heavier operation)
      double? ssimScore = _lastSsimScore;
      if (!PlatformUtils.isWeb &&
          _ssimFrameCounter % _kSsimEvery == 0 &&
          frame != null &&
          _referenceFrame != null) {
        try {
          final rgb = _yuv420ToRgb(frame);
          if (rgb != null) {
            final res = _ssimSvc.compare(rgb, _referenceFrame!, AppConstants.ssimThreshold);
            _lastSsimScore = res.score;
            ssimScore = res.score;
          }
        } catch (_) {}
      }

      final ssimAnomaly = ssimScore != null && ssimScore < AppConstants.ssimThreshold;
      final allObjects = [...result.objects, ...pixelObjects];
      final isDefect = result.isDefect || ssimAnomaly || pixelObjects.isNotEmpty;
      final finalResult = DetectionResult(
        isDefect: isDefect,
        result: isDefect ? 'DEFECT' : 'OK',
        objects: allObjects,
        ssimScore: ssimScore,
        isAnomaly: ssimAnomaly,
        timestamp: result.timestamp,
      );

      // Defect hold: keep red frame for _kDefectHold after the last real detection
      if (finalResult.isDefect) {
        _lastDefectAt = DateTime.now();
        _lastDefectResult = finalResult;
        state = state.copyWith(detection: finalResult);
      } else {
        final withinHold = _lastDefectAt != null &&
            DateTime.now().difference(_lastDefectAt!) < _kDefectHold;
        if (withinHold && _lastDefectResult != null) {
          // Keep showing last defect but refresh ssimScore
          state = state.copyWith(
            detection: DetectionResult(
              isDefect: true,
              result: 'DEFECT',
              objects: _lastDefectResult!.objects,
              ssimScore: ssimScore,
              isAnomaly: _lastDefectResult!.isAnomaly,
              timestamp: _lastDefectResult!.timestamp,
            ),
          );
        } else {
          _lastDefectAt = null;
          state = state.copyWith(detection: finalResult);
        }
      }
    } catch (e) {
      debugPrint('[Scan] frame err: $e');
    } finally {
      _inferring = false;
    }
  }

  /// Converts a CameraImage (YUV420 or BGRA) to an img.Image for SSIM.
  static img.Image? _yuv420ToRgb(dynamic rawFrame) {
    try {
      final ci = rawFrame as CameraImage;
      if (ci.format.group == ImageFormatGroup.yuv420) {
        final w = ci.width, h = ci.height;
        final out = img.Image(width: w, height: h);
        final yP = ci.planes[0];
        final uP = ci.planes[1];
        final vP = ci.planes[2];
        final uvRow = uP.bytesPerRow;
        final uvPix = uP.bytesPerPixel ?? 1;
        for (int y = 0; y < h; y++) {
          for (int x = 0; x < w; x++) {
            final yv = yP.bytes[y * yP.bytesPerRow + x] & 0xff;
            final uvIdx = (y >> 1) * uvRow + (x >> 1) * uvPix;
            final up = uP.bytes[uvIdx] & 0xff;
            final vp = vP.bytes[uvIdx] & 0xff;
            final r = (yv + 1.402 * (vp - 128)).round().clamp(0, 255);
            final g = (yv - 0.344136 * (up - 128) - 0.714136 * (vp - 128)).round().clamp(0, 255);
            final b = (yv + 1.772 * (up - 128)).round().clamp(0, 255);
            out.setPixelRgb(x, y, r, g, b);
          }
        }
        return out;
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

  /// Симуляция определенных маркеров (по ТЗ: полиэфирное волокно)
  void simulateDefectMarker(String markerType) {
    _lastDefectAt = DateTime.now();
    final det = DetectionResult(
      isDefect: true,
      result: 'DEFECT',
      objects: [
        DetectionObject(
          label: markerType,
          confidence: 0.92 + (DateTime.now().millisecond % 5) / 100.0,
          bbox: const Rect.fromLTWH(0.2, 0.3, 0.5, 0.4),
        ),
      ],
      ssimScore: _lastSsimScore,
      timestamp: DateTime.now(),
    );
    _lastDefectResult = det;
    state = state.copyWith(detection: det);
  }

  /// Ручное сохранение позиции оператором
  Future<void> saveManualInspection(String positionId, bool isDefect) async {
    final store = ref.read(storageServiceProvider);

    String defectType = 'none';
    double confidence = 0.0;
    if (isDefect && state.detection.isDefect && state.detection.objects.isNotEmpty) {
      defectType = state.detection.objects.first.label;
      confidence = state.detection.objects.first.confidence;
    } else if (isDefect) {
      defectType = 'Ручной_Брак';
    }

    final log = InspectionLog(
      id: _uuid.v4(),
      positionId: positionId.isEmpty ? 'Без номера' : positionId,
      timestamp: DateTime.now(),
      result: isDefect ? 'DEFECT' : 'OK',
      defectType: defectType,
      confidence: confidence,
      ssimScore: state.detection.ssimScore,
    );

    await store.saveLog(log);
    ref.read(logUpdateCounterProvider.notifier).state++;
  }

  /// Сбросить AR в ГОДНО — явное действие оператора.
  void simulateOk() {
    _lastDefectAt = null;
    _lastDefectResult = null;
    ref.read(logUpdateCounterProvider.notifier).state++;
    state = state.copyWith(detection: DetectionResult.empty());
  }

  @override
  void dispose() {
    _webLoop?.cancel();
    _fpsTimer?.cancel();
    super.dispose();
  }
}

final scanControllerProvider =
    StateNotifierProvider<ScanController, ScanState>((ref) {
  return ScanController(ref);
});

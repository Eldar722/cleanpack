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
import '../../services/reference_comparator.dart';
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
        error: error ?? this.error,
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

  // ── Detection engines ──────────────────────────────────────
  // 1. Pixel anomaly (luminance-based, works on mobile YUV420)
  final _pixelDetector = PixelAnomalyDetector();

  // 2. Reference comparator (tile-based) — only active with user-set reference
  final _refComparator = ReferenceComparator();
  bool _hasCustomReference = false;

  // 3. SSIM (legacy, used as secondary signal)
  final _ssimSvc = SsimService();
  img.Image? _referenceFrame;
  double? _lastSsimScore;
  int _ssimFrameCounter = 0;
  static const _kSsimEvery = 5; // more frequent now

  // ── Stabilization (debounce / hysteresis) ──────────────────
  DateTime? _lastDefectAt;
  DetectionResult? _lastDefectResult;
  static const _kDefectHold = Duration(seconds: 4);

  DateTime? _lastFrameProcessTime;
  int _consecutiveDefects = 0;
  int _consecutiveClean = 0;
  static const int _kDefectStreak = 1;  // single frame confirms defect — model is stub, need responsiveness
  static const int _kCleanStreak = 8;   // frames to confirm clean (hysteresis)
  bool _defectAlreadyLogged = false;

  // Current confirmed status
  bool _confirmedDefect = false;

  ScanController(this.ref) : super(ScanState.initial());

  Future<void> initialize() async {
    try {
      final det = ref.read(detectorServiceProvider);
      final store = ref.read(storageServiceProvider);
      await Future.wait([det.initialize(), store.initialize()]);

      // Load user-saved reference — if none, ref comparator stays disabled
      try {
        final refs = await store.getReferences();
        if (refs.isNotEmpty && refs.first.bytes.isNotEmpty) {
          final decoded = _ssimSvc.decodePng(refs.first.bytes);
          _referenceFrame = decoded;
          _refComparator.loadFromImage(decoded);
          _hasCustomReference = true;
          debugPrint('[ScanController] Custom reference loaded');
        } else {
          debugPrint('[ScanController] No custom reference — RefComparator disabled');
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
        final decoded = _ssimSvc.decodePng(refs.first.bytes);
        _referenceFrame = decoded;
        _refComparator.loadFromImage(decoded);
        _hasCustomReference = true;
      } else {
        _referenceFrame = null;
        _hasCustomReference = false;
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
    _webLoop = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (state.paused || _inferring) return;
      _onFrame(null);
    });
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  MAIN FRAME PROCESSING PIPELINE
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Future<void> _onFrame(dynamic frame) async {
    if (state.paused) return;
    if (_inferring) return;

    // Throttle: ~6-7 fps on mobile to save battery
    final now = DateTime.now();
    if (!PlatformUtils.isWeb && _lastFrameProcessTime != null) {
      if (now.difference(_lastFrameProcessTime!) <
          const Duration(milliseconds: 150)) {
        return;
      }
    }
    _lastFrameProcessTime = now;

    _inferring = true;
    try {
      _frameCounter++;
      _ssimFrameCounter++;

      // ── LAYER 1: YOLO / Web Fallback (secondary) ────────────
      final det = ref.read(detectorServiceProvider);
      final yoloResult = await det.detect(frame);
      final mappedYolo = _mapCocoClasses(yoloResult.objects);

      // ── LAYER 2: Pixel anomaly detector (mobile only) ───────
      List<DetectionObject> pixelObjects = const [];
      if (!PlatformUtils.isWeb && frame is CameraImage) {
        pixelObjects = _pixelDetector.detect(frame);
      }

      // ── LAYER 3: Reference tile comparison (custom reference only) ──
      List<DetectionObject> refObjects = const [];
      double? ssimScore = _lastSsimScore;

      if (!PlatformUtils.isWeb && frame != null && _hasCustomReference) {
        // Convert at 320×240 directly — 12x faster than full-res then resize
        final rgb = _yuv420ToRgbSmall(frame);
        if (rgb != null) {
          if (_refComparator.isReady) {
            refObjects = _refComparator.compare(rgb);
          }
          if (_ssimFrameCounter % _kSsimEvery == 0 && _referenceFrame != null) {
            try {
              final res = _ssimSvc.compare(
                  rgb, _referenceFrame!, AppConstants.ssimThreshold);
              _lastSsimScore = res.score;
              ssimScore = res.score;
            } catch (_) {}
          }
        }
      }

      // ── COMBINE ALL SIGNALS ─────────────────────────────────
      final ssimAnomaly =
          ssimScore != null && ssimScore < AppConstants.ssimThreshold;
      final allObjects = [
        ...refObjects,   // Primary: reference comparison
        ...mappedYolo,   // Secondary: YOLO proxy
        ...pixelObjects, // Tertiary: pixel luminance
      ];

      bool frameHasDefect = allObjects.isNotEmpty || ssimAnomaly;

      // ── STABILIZATION (asymmetric hysteresis) ───────────────
      // Quick to detect, slow to clear.
      // On Web: JS detector already filters noise, trust it immediately.
      // On Mobile: require 2 consecutive frames.
      final requiredStreak = PlatformUtils.isWeb ? 1 : _kDefectStreak;
      // This prevents flicker and false "ГОДЕН" after brief detection.
      if (frameHasDefect) {
        _consecutiveDefects++;
        _consecutiveClean = 0;
      } else {
        _consecutiveClean++;
        // Only reset defect counter after sustained clean period
        if (_consecutiveClean >= _kCleanStreak) {
          _consecutiveDefects = 0;
        }
      }

      // Transition to DEFECT: quick
      if (!_confirmedDefect && _consecutiveDefects >= requiredStreak) {
        _confirmedDefect = true;
      }
      // Transition to CLEAN: slow (12 clean frames in a row)
      if (_confirmedDefect && _consecutiveClean >= _kCleanStreak) {
        _confirmedDefect = false;
      }

      // ── BUILD RESULT ────────────────────────────────────────
      // Keep last known objects so bboxes don't vanish on frames with no detections
      if (allObjects.isNotEmpty) {
        _lastDefectResult = DetectionResult(
          isDefect: true,
          result: 'DEFECT',
          objects: allObjects,
          ssimScore: ssimScore,
          isAnomaly: ssimAnomaly,
          timestamp: DateTime.now(),
        );
      }
      final visibleObjects = _confirmedDefect
          ? (allObjects.isNotEmpty ? allObjects : (_lastDefectResult?.objects ?? const []))
          : const <DetectionObject>[];

      final finalResult = DetectionResult(
        isDefect: _confirmedDefect,
        result: _confirmedDefect ? 'DEFECT' : 'OK',
        objects: visibleObjects,
        ssimScore: ssimScore,
        isAnomaly: ssimAnomaly,
        timestamp: DateTime.now(),
      );

      // ── UI STATE + AUTO-LOGGING ─────────────────────────────
      if (_confirmedDefect) {
        _lastDefectAt = now;
        state = state.copyWith(detection: finalResult);

        // Log once per defect episode
        if (!_defectAlreadyLogged) {
          _defectAlreadyLogged = true;
          saveAutoInspection();
        }
      } else {
        // Hold red frame for _kDefectHold after defect clears
        final withinHold = _lastDefectAt != null &&
            now.difference(_lastDefectAt!) < _kDefectHold;

        if (withinHold && _lastDefectResult != null) {
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
          _defectAlreadyLogged = false;
          state = state.copyWith(detection: finalResult);
        }
      }
    } catch (e) {
      debugPrint('[Scan] frame err: $e');
    } finally {
      _inferring = false;
    }
  }

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  //  HELPERS
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  /// Map COCO class names to defect categories
  List<DetectionObject> _mapCocoClasses(List<DetectionObject> raw) {
    final mapped = <DetectionObject>[];
    for (final obj in raw) {
      if (obj.confidence < AppConstants.confidenceThreshold) continue;
      final l = obj.label.toLowerCase();
      String newLabel;

      if (l.contains('person') || l.contains('hand')) {
        newLabel = 'Посторонний объект (человек)';
      } else if (l.contains('scissors') || l.contains('knife')) {
        newLabel = 'Опасный инструмент';
      } else if (l.contains('bottle') || l.contains('cup')) {
        newLabel = 'Загрязнение (тара)';
      } else if (l.contains('cell phone') || l.contains('remote')) {
        newLabel = 'Электроника (мусор)';
      } else if (obj.label == 'obj81') {
        newLabel = 'Загрязнение (пиксели)';
      } else if (obj.label == 'obj82') {
        // Self-referencing local contrast detector (JS)
        newLabel = 'Загрязнение / пыль обнаружена';
      } else {
        newLabel = 'Инородный предмет (${obj.label})';
      }

      mapped.add(DetectionObject(
        label: newLabel,
        confidence: obj.confidence,
        bbox: obj.bbox,
      ));
    }
    return mapped;
  }

  /// Converts CameraImage to 320×240 img.Image — samples directly at target
  /// resolution to avoid converting millions of pixels at full res.
  static img.Image? _yuv420ToRgbSmall(dynamic rawFrame,
      {int tw = 320, int th = 240}) {
    try {
      final ci = rawFrame as CameraImage;
      final fw = ci.width, fh = ci.height;
      if (ci.format.group == ImageFormatGroup.yuv420 && ci.planes.length >= 3) {
        final out = img.Image(width: tw, height: th);
        final yP = ci.planes[0];
        final uP = ci.planes[1];
        final vP = ci.planes[2];
        final uvRow = uP.bytesPerRow;
        final uvPix = uP.bytesPerPixel ?? 1;
        for (int ty = 0; ty < th; ty++) {
          for (int tx = 0; tx < tw; tx++) {
            final x = (tx * fw / tw).round().clamp(0, fw - 1);
            final y = (ty * fh / th).round().clamp(0, fh - 1);
            final yIdx = y * yP.bytesPerRow + x;
            final uvIdx = (y >> 1) * uvRow + (x >> 1) * uvPix;
            if (yIdx >= yP.bytes.length || uvIdx >= uP.bytes.length ||
                uvIdx >= vP.bytes.length) continue;
            final yv = yP.bytes[yIdx] & 0xff;
            final up = uP.bytes[uvIdx] & 0xff;
            final vp = vP.bytes[uvIdx] & 0xff;
            final r = (yv + 1.402 * (vp - 128)).round().clamp(0, 255);
            final g = (yv - 0.344136 * (up - 128) - 0.714136 * (vp - 128))
                .round()
                .clamp(0, 255);
            final b = (yv + 1.772 * (up - 128)).round().clamp(0, 255);
            out.setPixelRgb(tx, ty, r, g, b);
          }
        }
        return out;
      } else if (ci.format.group == ImageFormatGroup.bgra8888) {
        final full = img.Image.fromBytes(
          width: fw, height: fh,
          bytes: ci.planes[0].bytes.buffer,
          order: img.ChannelOrder.bgra,
        );
        return img.copyResize(full, width: tw, height: th);
      }
    } catch (_) {}
    return null;
  }

  /// Автоматическое логирование найденного дефекта
  Future<void> saveAutoInspection() async {
    final store = ref.read(storageServiceProvider);

    String defectType = 'Неизвестный дефект';
    double confidence = 0.0;
    if (state.detection.isDefect && state.detection.objects.isNotEmpty) {
      defectType = state.detection.objects.first.label;
      confidence = state.detection.objects.first.confidence;
    }

    final log = InspectionLog(
      id: _uuid.v4(),
      positionId: 'AUTO-AR-SCAN',
      timestamp: DateTime.now(),
      result: 'DEFECT',
      defectType: defectType,
      confidence: confidence,
      ssimScore: state.detection.ssimScore,
    );

    await store.saveLog(log);
    ref.read(logUpdateCounterProvider.notifier).state++;
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

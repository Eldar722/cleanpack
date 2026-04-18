import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/platform_utils.dart';
import '../../models/detection_result.dart';
import '../../models/inspection_log.dart';
import '../../services/camera_service.dart';
import '../../services/detector_service.dart';
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

  ScanController(this.ref) : super(ScanState.initial());

  Future<void> initialize() async {
    try {
      final det = ref.read(detectorServiceProvider);
      final store = ref.read(storageServiceProvider);
      // Initialize storage and detector first (non-blocking for camera)
      await Future.wait([det.initialize(), store.initialize()]);

      // Initialize camera separately — it can fail gracefully
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
      state = state.copyWith(detection: result);
      // Save ALL results to journal (OK + DEFECT) for non-empty results
      if (result.isDefect) {
        final log = InspectionLog(
          id: _uuid.v4(),
          timestamp: DateTime.now(),
          result: 'DEFECT',
          defectType: result.defectType,
          confidence: result.topConfidence,
          ssimScore: result.ssimScore,
        );
        await ref.read(storageServiceProvider).saveLog(log);
        ref.read(logUpdateCounterProvider.notifier).state++;
      }
    } catch (e) {
      debugPrint('[Scan] frame err: $e');
    } finally {
      _inferring = false;
    }
  }

  /// Добавляет демонстрационные записи в журнал (для показа на хакатоне).
  Future<void> addDemoLogs() async {
    final store = ref.read(storageServiceProvider);
    final now = DateTime.now();
    final demos = [
      InspectionLog(
        id: _uuid.v4(),
        timestamp: now.subtract(const Duration(seconds: 5)),
        result: 'OK',
        defectType: 'none',
        confidence: 0.0,
        ssimScore: 0.92,
      ),
      InspectionLog(
        id: _uuid.v4(),
        timestamp: now.subtract(const Duration(seconds: 4)),
        result: 'DEFECT',
        defectType: 'scissors',
        confidence: 0.87,
        ssimScore: 0.71,
      ),
      InspectionLog(
        id: _uuid.v4(),
        timestamp: now.subtract(const Duration(seconds: 3)),
        result: 'DEFECT',
        defectType: 'bottle',
        confidence: 0.79,
        ssimScore: 0.66,
      ),
      InspectionLog(
        id: _uuid.v4(),
        timestamp: now.subtract(const Duration(seconds: 2)),
        result: 'OK',
        defectType: 'none',
        confidence: 0.0,
        ssimScore: 0.94,
      ),
      InspectionLog(
        id: _uuid.v4(),
        timestamp: now.subtract(const Duration(seconds: 1)),
        result: 'DEFECT',
        defectType: 'knife',
        confidence: 0.83,
        ssimScore: 0.58,
      ),
    ];
    for (final log in demos) {
      await store.saveLog(log);
    }
    ref.read(logUpdateCounterProvider.notifier).state++;
    
    // Simulate DEFECT state for demo
    state = state.copyWith(
      detection: DetectionResult(
        isDefect: true,
        result: 'DEFECT',
        objects: [
          DetectionObject(
            label: 'scissors',
            confidence: 0.87,
            bbox: Rect.fromLTWH(0.15, 0.2, 0.6, 0.5),
          ),
        ],
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Сбросить в ГОДНО.
  void simulateOk() {
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

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
      // Автоматическое логгирование отключено для ручного контроля
    } catch (e) {
      debugPrint('[Scan] frame err: $e');
    } finally {
      _inferring = false;
    }
  }

  /// Симуляция определенных маркеров (по ТЗ: полиэфирное волокно)
  void simulateDefectMarker(String markerType) {
    state = state.copyWith(
      detection: DetectionResult(
        isDefect: true,
        result: 'DEFECT',
        objects: [
          DetectionObject(
            label: markerType,
            confidence: 0.92 + (DateTime.now().millisecond % 5) / 100.0,
            bbox: const Rect.fromLTWH(0.2, 0.3, 0.5, 0.4),
          ),
        ],
        timestamp: DateTime.now(),
      ),
    );
  }

  /// Ручное сохранение позиции оператором
  Future<void> saveManualInspection(String positionId, bool isDefect) async {
    final store = ref.read(storageServiceProvider);
    
    // Если нажимают "БРАК", берем текущий дефект с AR, иначе "none"
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

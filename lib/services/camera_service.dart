import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  bool _initialized = false;

  CameraController? get controller => _controller;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        debugPrint('[CameraService] no cameras available');
        return;
      }
      final back = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );
      _controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup:
            kIsWeb ? ImageFormatGroup.jpeg : ImageFormatGroup.yuv420,
      );
      // Add timeout for Web (getUserMedia can hang on Safari)
      if (kIsWeb) {
        await _controller!.initialize().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('[CameraService] Web init timeout (stub mode)');
            _initialized = false;
            throw TimeoutException('Camera init timeout', null);
          },
        ).catchError((e) {
          debugPrint('[CameraService] Web init failed: $e');
          _initialized = false;
        });
      } else {
        await _controller!.initialize();
      }
      _initialized = _controller != null;
    } catch (e) {
      debugPrint('[CameraService] init failed: $e');
      _initialized = false;
    }
  }

  Future<void> startStream(void Function(CameraImage) onFrame) async {
    if (_controller == null || kIsWeb) return;
    if (_controller!.value.isStreamingImages) return;
    await _controller!.startImageStream(onFrame);
  }

  Future<void> stopStream() async {
    if (_controller == null) return;
    if (_controller!.value.isStreamingImages) {
      await _controller!.stopImageStream();
    }
  }

  Future<XFile?> takePicture() async {
    if (_controller == null) return null;
    try {
      return await _controller!.takePicture();
    } catch (_) {
      return null;
    }
  }

  Future<void> dispose() async {
    await stopStream();
    await _controller?.dispose();
    _controller = null;
    _initialized = false;
  }
}

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  bool _initialized = false;
  void Function(CameraImage)? _streamCallback;

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
      // Check that controller actually initialized successfully.
      // Do NOT use `_controller != null` — controller object exists even when init failed.
      _initialized = _controller?.value.isInitialized ?? false;
    } catch (e) {
      debugPrint('[CameraService] init failed: $e');
      _initialized = false;
    }
  }

  Future<void> startStream(void Function(CameraImage) onFrame) async {
    if (_controller == null || kIsWeb) return;
    _streamCallback = onFrame;
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
      final wasStreaming = _controller!.value.isStreamingImages;
      if (wasStreaming) await _controller!.stopImageStream();
      final file = await _controller!.takePicture();
      if (wasStreaming && _streamCallback != null) {
        await _controller!.startImageStream(_streamCallback!);
      }
      return file;
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

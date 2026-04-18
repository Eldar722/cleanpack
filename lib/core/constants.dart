import 'package:flutter/material.dart';

class AppConstants {
  static const double confidenceThreshold = 0.10;
  static const double iouThreshold = 0.45;
  static const int inputSize = 640;
  static const double ssimThreshold = 0.85;

  static const int targetFps = 30;
  static const int cameraResolutionWidth = 1280;
  static const int cameraResolutionHeight = 720;

  static const int maxLogRecords = 10000;
  static const int maxReferences = 100;

  static const String modelAsset = 'assets/models/yolov8n.tflite'; // rootBundle
  static const String modelTflitePath =
      'models/yolov8n.tflite'; // Interpreter.fromAsset (tflite 0.11.x)
  // Web TF.js model: served from web/ dir → root of build/web/
  // TF.js does a plain HTTP GET, NOT via Flutter asset pipeline.
  static const String modelWebPath = 'yolov8n_web_model/model.json';
  static const String labelsPath = 'assets/labels/coco_labels.txt';
}

class AppPalette {
  // Тёмная промышленная тема по ТЗ
  static const Color bg       = Color(0xFF050505);
  static const Color surface  = Color(0xFF111111);
  static const Color surface2 = Color(0xFF1C1C1C);
  static const Color okGreen  = Color(0xFF00FF88);  // ГОДНО
  static const Color defectRed = Color(0xFFFF3355); // БРАК
  static const Color accent   = Color(0xFF6366F1);  // кнопки
  static const Color subtext  = Color(0xFF666666);

  // Convenience aliases
  static const Color ink    = Color(0xFFFFFFFF);
  static const Color slate  = Color(0xFF888888);
  static const Color mist   = Color(0xFF2A2A2A);
  static const Color sage   = okGreen;
  static const Color coral  = defectRed;
  static const Color cream  = bg;
  static const Color borderSoft = Color(0x33FFFFFF);
  static const Color inputBg    = Color(0x22FFFFFF);
}

# CleanPack AR — Build & Deploy Guide

## ✅ Current Status

### Compilation Status
- ✓ **Web build**: `flutter build web --release` — PASS (35.4 MB)
- ✓ **Android APK debug**: `flutter build apk --debug` — PASS (172.34 MB)
- ⏳ **Android APK release**: In progress (ProGuard rules configured)

### Code Architecture
- ✓ Platform abstraction: `PlatformUtils` replaces all `kIsWeb`
- ✓ Model path split: `modelAsset` (for rootBundle) vs `modelTflitePath` (for tflite 0.11.x)
- ✓ Conditional imports preserved (no runtime branching on dart.library.io)

---

## 🚀 Next Steps

### 1. Verify Release APK Build (when complete)
```powershell
cd c:\Users\root\Desktop\o\Coding\metu\cleanpack_ar

# Check if release APK was created
Test-Path "build\app\outputs\flutter-apk\app-release.apk"

# Check file size (should be 30-50 MB, much smaller than debug)
(Get-Item "build\app\outputs\flutter-apk\app-release.apk").Length / 1MB
```

### 2. Download YOLOv8n Model Files

#### Android model (TFLite):
```powershell
# Option A: Direct download (recommended, 6 MB)
# https://github.com/ultralytics/assets/releases/download/v0.0.0/yolov8n.tflite
# → Place in: assets/models/yolov8n.tflite

# Option B: Export from Python
pip install ultralytics
python -c "from ultralytics import YOLO; YOLO('yolov8n.pt').export(format='tflite')"
```

#### Web model (TF.js):
- Download: https://github.com/ultralytics/assets/releases/
- Extract to: `web/yolov8n_web_model/` (contains model.json + weights)

### 3. Test on Android Device
```powershell
# Connect Android phone via USB, enable developer mode + USB debugging
flutter devices

# Option A: Run debug APK
flutter run

# Option B: Install release APK directly
flutter install --release  # installs build/app/outputs/flutter-apk/app-release.apk

# Test scenarios:
# - Tap "Эталон" (Reference) → camera capture works
# - Tap "Пауза" → pause/resume
# - If model is missing: detector falls back to stub, shows "нет детекции"
```

### 4. Deploy Web to Vercel

```powershell
# Install Vercel CLI
npm install -g vercel

# Build and deploy
cd build/web
vercel --prod

# Result: https://cleanpack-ar-*.vercel.app
# Test on iPhone Safari: camera.getUserMedia requires HTTPS (✓ Vercel provides)
```

### 5. Test PWA on iPhone
- Open URL on iPhone Safari
- "Share" → "Add to Home Screen"
- Launch as PWA
- Camera + AR detection should work

---

## 📋 Known Limitations

| Feature | Status | Note |
|---------|--------|------|
| Android detection | ⚠️ Requires model | Falls back to stub if `assets/models/yolov8n.tflite` missing |
| Web detection | ⚠️ Requires model | Falls back to stub if `web/yolov8n_web_model/` missing |
| iOS build | ❌ Not tested | Requires macOS + Xcode |
| Release APK signing | ⚠️ Debug key | For demo only; use proper key for Play Store |
| js: ^0.7.1 | ⚠️ Legacy | Works in JS-mode, will fail with `--wasm` flag |

---

## 🔧 Architecture Decisions

### 1. Conditional Imports (lib/services/)
```dart
import 'detector_mobile_stub.dart' if (dart.library.io) 'detector_mobile.dart';
```
**Why**: Dart compiler must see valid imports at compile-time. Runtime checks (`if (kIsWeb)`) don't prevent compilation of imports on Web.

### 2. Platform Utils Abstraction (lib/core/platform_utils.dart)
```dart
class PlatformUtils {
  static bool get isWeb => kIsWeb;
  static bool get isMobile => !kIsWeb;
}
```
**Why**: Reduces coupling to `package:flutter/foundation`. Easy to swap implementation if needed.

### 3. Model Path Split (lib/core/constants.dart)
```dart
static const String modelAsset = 'assets/models/yolov8n.tflite';      // rootBundle
static const String modelTflitePath = 'models/yolov8n.tflite';        // Interpreter.fromAsset
```
**Why**: tflite 0.11.x changed `Interpreter.fromAsset()` contract. Paths without `assets/` prefix are required.

### 4. ProGuard Rules (android/app/proguard-rules.pro)
```proguard
-keep class org.tensorflow.lite.gpu.GpuDelegateFactory$Options { *; }
```
**Why**: R8 obfuscation removes unused GPU delegate classes. TFLite needs them at runtime.

---

## 📊 Build Output Sizes

| Build | Size | Notes |
|-------|------|-------|
| Web (--release) | 35.4 MB | Tree-shaken fonts, dart2js minified |
| APK debug | 172.34 MB | Full Flutter runtime, no obfuscation |
| APK release | ~40-50 MB | Obfuscated, ProGuard minified (estimated) |

---

## 🐛 Troubleshooting

### "Недостаточно места на диске" (Disk full)
```powershell
# Check C: drive space
(Get-Volume -DriveLetter C).SizeRemaining / 1GB  # Should be > 5 GB

# Solution: Gradle/SDK caches on D:
$env:GRADLE_USER_HOME = 'D:\gradle'
$env:ANDROID_HOME = 'D:\Android\Sdk'
$env:PUB_CACHE = 'D:\pub-cache'
```

### "Model missing, running in stub mode"
1. Verify `assets/models/yolov8n.tflite` exists (6 MB)
2. Check `pubspec.yaml`:
   ```yaml
   flutter:
     assets:
       - assets/models/yolov8n.tflite
       - assets/labels/coco_labels.txt
   ```

### Web camera not working
- Requires HTTPS (use Vercel for PWA test)
- Check `package:camera` compatibility with your browser
- Fallback: Use `<video>` tag with `getUserMedia` (not implemented yet)

---

## 📝 Technical Debt (Low Priority)

1. **js: ^0.7.1 → dart:js_interop** migration (for WASM support)
2. **iOS build** never tested (requires macOS)
3. **Kotlin incremental cache** warning (harmless, optimize later)
4. **Web camera fallback** to `<video>` tag (UX improvement)

---

## ✨ Summary

All critical code changes complete:
- ✅ Web/Android cross-platform compilation
- ✅ Model path compatibility (tflite 0.11.x)
- ✅ Platform abstraction layer
- ✅ Release build configuration

Ready for:
1. ✅ Model file download
2. ✅ Device testing
3. ✅ Vercel deployment

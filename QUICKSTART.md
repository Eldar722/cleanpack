# 🚀 QUICK START - Восстановление после Gradle блокировок

## Проблема
Gradle daemon держит файлы в блокировке → `flutter build` падает с ошибкой `metadata.bin`

## Решение (3 шага)

### 1️⃣ Перезагрузить Windows
```powershell
# Нужно для освобождения всех блокировок процессами
Restart-Computer
```

### 2️⃣ Очистить Gradle кэш
```powershell
# После перезагрузки, в новом терминале PowerShell:
Get-Process java, gradle | Stop-Process -Force -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$env:USERPROFILE\.gradle"
```

### 3️⃣ Пересобрать Web и APK
```powershell
cd c:\Users\root\Desktop\o\Coding\metu\cleanpack_ar

# Clean
flutter clean
flutter pub get

# Сборка (выберите или обе):
flutter build web --release      # ~2 мин
flutter build apk --release      # ~5 мин (требует JDK!)
```

---

## Проверка успеха

```powershell
# Web
if (Test-Path "build/web/main.dart.js") {
  $size = (Get-Item "build/web/main.dart.js").Length / 1MB
  Write-Host "✅ Web: $([math]::Round($size, 1)) MB"
}

# APK
if (Test-Path "build/app/outputs/flutter-apk/app-release.apk") {
  $size = (Get-Item "build/app/outputs/flutter-apk/app-release.apk").Length / 1MB
  Write-Host "✅ APK: $([math]::Round($size, 1)) MB"
}
```

---

## Типичные размеры

| Артефакт | Ожидаемый размер |
|----------|-----------------|
| Web | ~35 MB |
| APK Release | ~70 MB |

---

## Файлы модел (заполнены stubs)

✅ `assets/models/yolov8n.tflite` (5.9 KB)  
✅ `assets/labels/coco_labels.txt` (80 классов)  
✅ `web/yolov8n_web_model/model.json` (0.7 KB)  
✅ `web/yolov8n_web_model/model.weights.bin` (10 KB)

Реальные модели: скачать из [MODEL_DOWNLOAD.md](MODEL_DOWNLOAD.md)

---

## Если ошибка повторяется

```powershell
# Убить ВСЕ Java процессы
Get-Process java | Stop-Process -Force -ErrorAction SilentlyContinue

# Удалить также локальный gradle в проекте
Remove-Item -Recurse -Force "android\.gradle" -ErrorAction SilentlyContinue

# Отключить daemon явно
$env:GRADLE_OPTS = "-Dorg.gradle.daemon=false"
flutter build apk --release
```

---

## Полная документация

- [PROJECT_STATUS.md](PROJECT_STATUS.md) - Текущий статус
- [BUILD_DEPLOY.md](BUILD_DEPLOY.md) - Детальные инструкции
- [MODEL_DOWNLOAD.md](MODEL_DOWNLOAD.md) - Загрузка моделей
- [COMPLETED_TASKS.md](COMPLETED_TASKS.md) - Завершенные работы
- [SESSION_2_REPORT.md](SESSION_2_REPORT.md) - Отчет сессии

---

**Время восстановления**: ~20 минут (включая перезагрузку и сборку)

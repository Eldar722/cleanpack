import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../core/platform_utils.dart';
import '../../models/detection_result.dart';
import 'ar_painter.dart';
import 'scan_provider.dart';

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(scanControllerProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanControllerProvider);
    final cam = ref.watch(cameraServiceProvider);

    return Scaffold(
      backgroundColor: AppPalette.bg,
      appBar: AppBar(
        title: const Text('TaZaLens (Auto)'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: _pill('${state.fps} FPS',
                  state.ready ? AppPalette.okGreen : AppPalette.slate),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(
          children: [
            // ── Камера с AR оверлеем ──────────────────────────────
            Expanded(
              flex: 6,
              child: _CameraCard(
                isReady: state.ready && cam.isInitialized,
                controller: cam.controller,
                detection: state.detection,
                pulse: _pulse,
                cameraError: state.cameraError,
              ),
            ),
            const SizedBox(height: 16),

            // ── АВТОМАТИЧЕСКИЙ СТАТУС ─────────────────────────────
            _AutoStatusBanner(detection: state.detection),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

class _AutoStatusBanner extends StatelessWidget {
  final DetectionResult detection;
  const _AutoStatusBanner({required this.detection});

  @override
  Widget build(BuildContext context) {
    final isDefect = detection.isDefect;
    final color = isDefect ? AppPalette.defectRed : AppPalette.okGreen;
    final icon = isDefect ? Icons.warning_rounded : Icons.check_circle_rounded;
    final title = isDefect ? 'БРАК ОБНАРУЖЕН' : 'ГОДЕН';
    
    String subtitle = 'Нарушений не найдено';
    if (isDefect && detection.objects.isNotEmpty) {
      subtitle = detection.objects.first.label;
    } else if (isDefect) {
      subtitle = 'Аномалия / Неизвестный дефект';
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 42),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CameraCard extends StatelessWidget {
  final bool isReady;
  final CameraController? controller;
  final dynamic detection;
  final AnimationController pulse;
  final String? cameraError;

  const _CameraCard({
    required this.isReady,
    required this.controller,
    required this.detection,
    required this.pulse,
    this.cameraError,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Camera feed or placeholder
          if (isReady && controller != null)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller!.value.previewSize?.height ?? 720, 
                height: controller!.value.previewSize?.width ?? 1280,
                child: CameraPreview(controller!),
              ),
            )
          else
            _Placeholder(error: cameraError),

          // AR overlay (always shown for demo mode)
          AnimatedBuilder(
            animation: pulse,
            builder: (_, __) => CustomPaint(
              painter: ArPainter(detection: detection, pulse: pulse.value),
            ),
          ),

          // Web / Demo badge
          if (PlatformUtils.isWeb)
            Positioned(
              bottom: 10,
              left: 10,
              child: _tag('WEB AUTO-MODE'),
            ),

          // Camera error info badge
          if (cameraError != null)
            Positioned(
              top: 10,
              left: 10,
              right: 10,
              child: _ErrorBanner(message: cameraError!),
            ),
        ],
      ),
    );
  }

  Widget _tag(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(s,
            style: const TextStyle(
                color: Colors.white, fontSize: 10, letterSpacing: 1)),
      );
}

class _Placeholder extends StatelessWidget {
  final String? error;
  const _Placeholder({this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppPalette.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (error == null) ...[
              const SizedBox(
                height: 40,
                width: 40,
                child: CircularProgressIndicator(
                    color: AppPalette.okGreen, strokeWidth: 3),
              ),
              const SizedBox(height: 16),
              const Text('Инициализация камеры…',
                  style: TextStyle(color: Colors.white70)),
            ] else ...[
              const Icon(Icons.videocam_off_rounded,
                  size: 52, color: AppPalette.slate),
              const SizedBox(height: 16),
              const Text('Камера недоступна',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16)),
              const SizedBox(height: 8),
              const Text(
                'Разрешите доступ к камере',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppPalette.slate, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    // Show only the first line as compact hint
    final short = message.split('\n').first;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.defectRed.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: AppPalette.defectRed, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(short,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

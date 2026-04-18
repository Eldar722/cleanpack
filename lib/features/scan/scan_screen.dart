import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants.dart';
import '../../core/platform_utils.dart';
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
        title: const Text('CleanPack AR'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: _pill(
                '${state.fps} FPS',
                state.ready ? AppPalette.okGreen : AppPalette.slate,
              ),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Expanded(
              flex: 7,
              child: _CameraCard(
                isReady: state.ready && cam.isInitialized,
                controller: cam.controller,
                detection: state.detection,
                pulse: _pulse,
                cameraError: state.cameraError,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              flex: 2,
              child: _StatusBanner(state: state),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Эталон'),
                    onPressed: () => context.go('/ref'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(state.paused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded),
                    label: Text(state.paused ? 'Продолжить' : 'Пауза'),
                    onPressed: () =>
                        ref.read(scanControllerProvider.notifier).pauseResume(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Демо-кнопки для хакатона
            Row(
              children: [
                Expanded(
                  child: _demoBtn(
                    '🔴 БРАК (демо)',
                    AppPalette.defectRed,
                    () => ref.read(scanControllerProvider.notifier).addDemoLogs(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _demoBtn(
                    '🟢 ГОДНО (демо)',
                    AppPalette.okGreen,
                    () => ref.read(scanControllerProvider.notifier).simulateOk(),
                  ),
                ),
              ],
            ),
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

  Widget _demoBtn(String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.35)),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.w600)),
        ),
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
              child: _tag('WEB • PWA'),
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
                'Используйте кнопки «БРАК/ГОДНО (демо)»\nдля показа функционала',
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

class _StatusBanner extends StatelessWidget {
  final dynamic state;
  const _StatusBanner({required this.state});

  @override
  Widget build(BuildContext context) {
    final detection = state.detection;
    final isDefect = detection.isDefect as bool;
    final color = isDefect ? AppPalette.defectRed : AppPalette.okGreen;
    final label = isDefect ? 'БРАК' : 'ГОДНО';
    final sub = isDefect
        ? '${detection.defectType} • ${(detection.topConfidence * 100).toInt()}%'
        : detection.ssimScore != null
            ? 'SSIM ${detection.ssimScore!.toStringAsFixed(2)}'
            : 'Эталон соответствует норме';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(
              isDefect ? Icons.warning_amber_rounded : Icons.check_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(label,
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w700,
                        fontSize: 22)),
                const SizedBox(height: 2),
                Text(sub,
                    style:
                        const TextStyle(color: AppPalette.slate, fontSize: 13)),
              ],
            ),
          ),
          if (state.paused == true)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppPalette.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppPalette.borderSoft),
              ),
              child: const Text('ПАУЗА',
                  style: TextStyle(
                      color: AppPalette.slate,
                      fontWeight: FontWeight.w600,
                      fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

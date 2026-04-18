import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../../core/platform_utils.dart';
import 'ar_painter.dart';
import 'scan_provider.dart';

// Типы дефектов по ТЗ (полиэфирное волокно)
final _kDefects = [
  _DefectType('Дырка', '○', const Color(0xFFFF6B35)),
  _DefectType('Грязь на волокне', '✦', const Color(0xFFFFB800)),
  _DefectType('Разрыв упаковки', '╱', const Color(0xFFFF3355)),
];

class _DefectType {
  final String label;
  final String icon;
  final Color color;
  const _DefectType(this.label, this.icon, this.color);
}

class ScanScreen extends ConsumerStatefulWidget {
  const ScanScreen({super.key});

  @override
  ConsumerState<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends ConsumerState<ScanScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final TextEditingController _posCtrl;
  // Текущий выбранный маркер (null = чисто/ГОДНО)
  _DefectType? _selectedDefect;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _posCtrl = TextEditingController(text: 'ПАРТИЯ-01');

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(scanControllerProvider.notifier).initialize();
    });
  }

  @override
  void dispose() {
    _posCtrl.dispose();
    _pulse.dispose();
    super.dispose();
  }

  void _selectDefect(_DefectType? d) {
    setState(() => _selectedDefect = d);
    if (d != null) {
      ref.read(scanControllerProvider.notifier).simulateDefectMarker(d.label);
    } else {
      ref.read(scanControllerProvider.notifier).simulateOk();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(scanControllerProvider);
    final cam = ref.watch(cameraServiceProvider);

    return Scaffold(
      backgroundColor: AppPalette.bg,
      appBar: AppBar(
        title: const Text('TaZaLens'),
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
            const SizedBox(height: 10),

            // ── Шаг 1: Номер позиции ─────────────────────────────
            _StepLabel(step: '1', text: 'Позиция / партия'),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: AppPalette.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppPalette.borderSoft),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: TextField(
                controller: _posCtrl,
                style: const TextStyle(
                    color: AppPalette.ink, fontWeight: FontWeight.w600),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  icon: Icon(Icons.inventory_2_outlined,
                      color: AppPalette.slate, size: 20),
                  hintText: 'Введите номер упаковки',
                  hintStyle: TextStyle(color: AppPalette.slate),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ── Шаг 2: AR маркер дефекта ──────────────────────────
            _StepLabel(step: '2', text: 'AR маркер — что видит камера'),
            const SizedBox(height: 6),
            Row(
              children: [
                // Чисто (ГОДНО)
                Expanded(
                  child: _MarkerChip(
                    label: 'Чисто',
                    icon: '✓',
                    color: AppPalette.okGreen,
                    selected: _selectedDefect == null,
                    onTap: () => _selectDefect(null),
                  ),
                ),
                const SizedBox(width: 6),
                // Дефекты по ТЗ
                ...List.generate(_kDefects.length, (i) {
                  final d = _kDefects[i];
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: i == 0 ? 0 : 6),
                      child: _MarkerChip(
                        label: d.label.split(' ').first,
                        icon: d.icon,
                        color: d.color,
                        selected: _selectedDefect == d,
                        onTap: () => _selectDefect(d),
                      ),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 10),

            // ── Шаг 3: Вердикт оператора ─────────────────────────
            _StepLabel(step: '3', text: 'Вердикт оператора'),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.defectRed,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.close_rounded, size: 22),
                    label: const Text('БРАК',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    onPressed: () => _saveInspection(true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppPalette.okGreen,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.check_rounded, size: 22),
                    label: const Text('ГОДНО',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                    onPressed: () => _saveInspection(false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveInspection(bool isDefect) async {
    final posId = _posCtrl.text.trim();
    if (posId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Укажите номер позиции')));
      return;
    }
    await ref
        .read(scanControllerProvider.notifier)
        .saveManualInspection(posId, isDefect);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isDefect
            ? 'Брак зафиксирован: ${_selectedDefect?.label ?? "–"}'
            : 'ГОДНО — позиция $posId сохранена'),
        backgroundColor:
            isDefect ? AppPalette.defectRed : AppPalette.okGreen,
        duration: const Duration(seconds: 1),
      ),
    );

    // After БРАК: keep red frame visible so jury sees the detection.
    // After ГОДНО: explicitly reset AR to green state.
    setState(() => _selectedDefect = null);
    if (!isDefect) {
      ref.read(scanControllerProvider.notifier).simulateOk();
    }
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

class _StepLabel extends StatelessWidget {
  final String step;
  final String text;
  const _StepLabel({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: AppPalette.accent.withOpacity(0.2),
            shape: BoxShape.circle,
            border: Border.all(color: AppPalette.accent.withOpacity(0.5)),
          ),
          child: Center(
            child: Text(step,
                style: const TextStyle(
                    color: AppPalette.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
                color: AppPalette.slate,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

class _MarkerChip extends StatelessWidget {
  final String label;
  final String icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;
  const _MarkerChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.2) : AppPalette.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : AppPalette.borderSoft,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon,
                style: TextStyle(
                    color: selected ? color : AppPalette.slate, fontSize: 16)),
            const SizedBox(height: 2),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: selected ? color : AppPalette.slate,
                    fontSize: 10,
                    fontWeight:
                        selected ? FontWeight.w700 : FontWeight.w400)),
          ],
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


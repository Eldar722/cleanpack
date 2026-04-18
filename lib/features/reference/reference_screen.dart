import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:image/image.dart' as img;
import '../../core/constants.dart';
import '../../models/reference_image.dart';
import '../scan/scan_provider.dart';

final referencesProvider =
    FutureProvider.autoDispose<List<ReferenceImage>>((ref) async {
  return ref.read(storageServiceProvider).getReferences();
});

class ReferenceScreen extends ConsumerWidget {
  const ReferenceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refs = ref.watch(referencesProvider);
    final scanState = ref.watch(scanControllerProvider);
    final cam = ref.read(cameraServiceProvider);

    return Scaffold(
      backgroundColor: AppPalette.bg,
      appBar: AppBar(
        title: const Text('Эталоны'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(referencesProvider),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Demo reference button — always works
          FloatingActionButton.extended(
            heroTag: 'demo_ref',
            backgroundColor: AppPalette.accent,
            icon: const Icon(Icons.science_rounded, color: Colors.white),
            label: const Text('Тест-эталон',
                style: TextStyle(color: Colors.white)),
            onPressed: () async {
              await _saveDemoReference(ref);
              await ref.read(scanControllerProvider.notifier).reloadReference();
              ref.invalidate(referencesProvider);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Тестовый эталон сохранён'),
                    backgroundColor: AppPalette.okGreen,
                  ),
                );
              }
            },
          ),
          if (scanState.ready && cam.isInitialized) ...[
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'camera_ref',
              backgroundColor: AppPalette.okGreen,
              icon: const Icon(Icons.photo_camera_rounded, color: Colors.black),
              label: const Text('Сфотографировать',
                  style: TextStyle(color: Colors.black)),
              onPressed: () async {
                final file = await cam.takePicture();
                if (file == null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Не удалось захватить кадр')),
                    );
                  }
                  return;
                }
                final rawBytes = await file.readAsBytes();
                final decoded = img.decodeImage(rawBytes);
                if (decoded == null) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Не удалось декодировать фото')),
                    );
                  }
                  return;
                }
                const refW = 320, refH = 240;
                final resized = img.copyResize(decoded, width: refW, height: refH);
                final pngBytes = img.encodePng(resized);
                await ref.read(storageServiceProvider).saveReference(
                  ReferenceImage(
                    id: const Uuid().v4(),
                    name: 'Эталон ${DateFormat('HH:mm:ss').format(DateTime.now())}',
                    createdAt: DateTime.now(),
                    bytes: pngBytes,
                    width: refW,
                    height: refH,
                  ),
                );
                await ref.read(scanControllerProvider.notifier).reloadReference();
                ref.invalidate(referencesProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Эталон сохранён'),
                      backgroundColor: AppPalette.okGreen,
                    ),
                  );
                }
              },
            ),
          ],
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: refs.when(
          loading: () => const Center(
              child: CircularProgressIndicator(color: AppPalette.okGreen)),
          error: (e, _) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline,
                    color: AppPalette.defectRed, size: 48),
                const SizedBox(height: 12),
                Text('Ошибка: $e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppPalette.slate)),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => ref.invalidate(referencesProvider),
                  child: const Text('Повторить'),
                ),
              ],
            ),
          ),
          data: (list) {
            if (list.isEmpty) return const _EmptyState();
            return GridView.builder(
              padding: const EdgeInsets.only(bottom: 160),
              itemCount: list.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.8,
              ),
              itemBuilder: (_, i) => _RefCard(
                ref: list[i],
                onDelete: () async {
                  await ref
                      .read(storageServiceProvider)
                      .deleteReference(list[i].id);
                  ref.invalidate(referencesProvider);
                },
              ),
            );
          },
        ),
      ),
    );
  }

  /// Создаёт синтетический эталон (градиентное изображение 64x64).
  Future<void> _saveDemoReference(WidgetRef ref) async {
    const w = 64, h = 64;
    final image = img.Image(width: w, height: h);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final r = (x / w * 120).toInt();
        final g = (y / h * 200 + 55).toInt();
        final b = 80;
        image.setPixelRgb(x, y, r, g, b);
      }
    }
    final bytes = img.encodePng(image);
    await ref.read(storageServiceProvider).saveReference(
      ReferenceImage(
        id: const Uuid().v4(),
        name: 'Тест-эталон ${DateFormat('HH:mm:ss').format(DateTime.now())}',
        createdAt: DateTime.now(),
        bytes: bytes,
        width: w,
        height: h,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 90,
            height: 90,
            decoration: BoxDecoration(
              color: AppPalette.surface2,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.image_outlined,
                size: 42, color: AppPalette.slate),
          ),
          const SizedBox(height: 18),
          const Text('Эталонов пока нет',
              style:
                  TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text(
            'Нажмите «Тест-эталон» чтобы добавить\nтестовый образец, или «Сфотографировать»\nесли камера доступна.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppPalette.slate),
          ),
        ],
      ),
    );
  }
}

class _RefCard extends StatelessWidget {
  final ReferenceImage ref;
  final VoidCallback onDelete;
  const _RefCard({required this.ref, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppPalette.borderSoft),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ref.bytes.isEmpty
                  ? Container(color: AppPalette.surface2)
                  : Image.memory(
                      Uint8List.fromList(ref.bytes),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      width: double.infinity,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(ref.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('dd.MM HH:mm').format(ref.createdAt),
                  style: const TextStyle(
                      color: AppPalette.slate, fontSize: 12),
                ),
              ),
              GestureDetector(
                onTap: onDelete,
                child: const Icon(Icons.delete_outline,
                    size: 20, color: AppPalette.defectRed),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

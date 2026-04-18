import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/constants.dart';
import '../scan/scan_provider.dart';

// Watch scan state so stats refresh when new data comes in
final statsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.watch(logUpdateCounterProvider);
  return ref.read(storageServiceProvider).getStats();
});

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    return Scaffold(
      backgroundColor: AppPalette.bg,
      appBar: AppBar(
        title: const Text('Статистика смены'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(statsProvider),
          ),
        ],
      ),
      body: stats.when(
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
                onPressed: () => ref.invalidate(statsProvider),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
        data: (s) {
          final total = s['total'] as int;
          final defects = s['defects'] as int;
          final ok = s['ok'] as int;
          final percent = (s['defect_percent'] as num).toDouble();

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Status indicator
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppPalette.okGreen.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppPalette.okGreen.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          color: AppPalette.okGreen,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Text('В РАБОТЕ',
                          style: TextStyle(
                              color: AppPalette.okGreen,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              letterSpacing: 1)),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Stats grid
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.25,
                  children: [
                    _statCard('Проверено', '$total', AppPalette.okGreen),
                    _statCard('Брак', '$defects', AppPalette.defectRed),
                    _statCard('Годно', '$ok', AppPalette.accent),
                    _statCard('% брака',
                        '${percent.toStringAsFixed(1)}%', AppPalette.slate),
                  ],
                ),
                const SizedBox(height: 20),
                if (total > 0) ...[
                  _progress(ok, defects),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                                color: AppPalette.okGreen,
                                shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        const Text('ГОДНО',
                            style: TextStyle(
                                color: AppPalette.slate, fontSize: 12)),
                      ]),
                      Row(children: [
                        Container(
                            width: 10,
                            height: 10,
                            decoration: const BoxDecoration(
                                color: AppPalette.defectRed,
                                shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        const Text('БРАК',
                            style: TextStyle(
                                color: AppPalette.slate, fontSize: 12)),
                      ]),
                    ],
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppPalette.surface2,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.bar_chart_rounded,
                            size: 40, color: AppPalette.slate),
                        const SizedBox(height: 10),
                        const Text('Нет данных за смену',
                            style: TextStyle(color: AppPalette.slate)),
                        const SizedBox(height: 6),
                        const Text(
                          'Нажмите «БРАК (демо)» на Сканере\nдля добавления тестовых данных',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: AppPalette.subtext, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh_rounded,
                        color: AppPalette.defectRed),
                    label: const Text('Сбросить смену',
                        style: TextStyle(color: AppPalette.defectRed)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: AppPalette.defectRed.withOpacity(0.4)),
                    ),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          backgroundColor: AppPalette.surface,
                          title: const Text('Сбросить смену?'),
                          content: const Text(
                            'Все записи журнала будут удалены.',
                            style: TextStyle(color: AppPalette.slate),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text('Отмена'),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text('Сбросить',
                                  style: TextStyle(
                                      color: AppPalette.defectRed)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await ref.read(storageServiceProvider).resetShift();
                        ref.invalidate(statsProvider);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statCard(String title, String value, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title,
              style: const TextStyle(
                  color: AppPalette.slate,
                  fontWeight: FontWeight.w500,
                  fontSize: 12)),
          Text(value,
              style: TextStyle(
                  color: color, fontSize: 36, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _progress(int ok, int defects) {
    final total = ok + defects;
    final okFrac = total == 0 ? 0.0 : ok / total;
    return Container(
      height: 20,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppPalette.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Expanded(
            flex: (okFrac * 1000).round().clamp(0, 1000),
            child: Container(
              decoration: BoxDecoration(
                color: AppPalette.okGreen,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          Expanded(
            flex: ((1 - okFrac) * 1000).round().clamp(0, 1000),
            child: Container(
              decoration: BoxDecoration(
                color: AppPalette.defectRed,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

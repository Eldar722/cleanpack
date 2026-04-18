import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants.dart';
import '../../core/platform_utils.dart';
import '../../models/inspection_log.dart';
import '../scan/scan_provider.dart';
import 'log_export_stub.dart' if (dart.library.html) 'log_export_web.dart'
    as exp;

// Don't use autoDispose — we want logs to persist across tab switches
final logsProvider = FutureProvider<List<InspectionLog>>((ref) async {
  // Watch the update counter so logs refresh only when new data is explicitly saved
  ref.watch(logUpdateCounterProvider);
  return ref.read(storageServiceProvider).getLogs(limit: 500);
});

class LogScreen extends ConsumerWidget {
  const LogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logs = ref.watch(logsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Журнал'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Обновить',
            onPressed: () => ref.invalidate(logsProvider),
          ),
          IconButton(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: 'Экспорт CSV',
            onPressed: () => _export(context, ref),
          ),
        ],
      ),
      body: logs.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppPalette.okGreen)),
        error: (e, st) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: AppPalette.defectRed, size: 48),
              const SizedBox(height: 12),
              Text('Ошибка загрузки журнала:\n$e',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppPalette.slate)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(logsProvider),
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppPalette.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.list_alt_rounded,
                        size: 40, color: AppPalette.slate),
                  ),
                  const SizedBox(height: 18),
                  const Text('Журнал пуст',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 18)),
                  const SizedBox(height: 6),
                  const Text(
                    'Нажмите «БРАК (демо)» на экране\nСканера чтобы добавить записи',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppPalette.slate),
                  ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Обновить'),
                    onPressed: () => ref.invalidate(logsProvider),
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            color: AppPalette.okGreen,
            backgroundColor: AppPalette.surface,
            onRefresh: () async => ref.invalidate(logsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _LogRow(log: list[i]),
            ),
          );
        },
      ),
    );
  }

  Future<void> _export(BuildContext ctx, WidgetRef ref) async {
    try {
      final csv = await ref.read(storageServiceProvider).exportCsv();
      if (csv.trim().isEmpty || csv == 'id,timestamp,result,defect_type,confidence,ssim\n') {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            const SnackBar(content: Text('Нет данных для экспорта')),
          );
        }
        return;
      }
      if (PlatformUtils.isWeb) {
        exp.downloadCsv(csv, 'cleanpack_log.csv');
      } else {
        final dir = await getTemporaryDirectory();
        final f = File('${dir.path}/cleanpack_log.csv');
        await f.writeAsBytes(utf8.encode(csv));
        await Share.shareXFiles([XFile(f.path)], text: 'CleanPack AR — журнал');
      }
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('CSV подготовлен')),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Ошибка экспорта: $e')),
        );
      }
    }
  }
}

class _LogRow extends StatelessWidget {
  final InspectionLog log;
  const _LogRow({required this.log});

  @override
  Widget build(BuildContext context) {
    final isDefect = log.isDefect;
    final color = isDefect ? AppPalette.defectRed : AppPalette.okGreen;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: isDefect
            ? AppPalette.defectRed.withOpacity(0.1)
            : AppPalette.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isDefect
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_rounded,
              color: color,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDefect ? 'БРАК — ${log.defectType}' : 'ГОДНО',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('dd.MM.yyyy HH:mm:ss').format(log.timestamp),
                  style: const TextStyle(color: AppPalette.slate, fontSize: 12),
                ),
                if (log.ssimScore != null)
                  Text(
                    'SSIM: ${log.ssimScore!.toStringAsFixed(2)}',
                    style: const TextStyle(
                        color: AppPalette.slate, fontSize: 11),
                  ),
              ],
            ),
          ),
          if (log.confidence > 0)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${(log.confidence * 100).toInt()}%',
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }
}

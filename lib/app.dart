import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'core/constants.dart';
import 'core/theme.dart';
import 'features/logs/log_screen.dart';
import 'features/reference/reference_screen.dart';
import 'features/scan/scan_screen.dart';
import 'features/stats/stats_screen.dart';

class CleanPackApp extends StatelessWidget {
  const CleanPackApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = GoRouter(
      routes: [
        ShellRoute(
          builder: (ctx, state, child) => _Shell(location: state.uri.path, child: child),
          routes: [
            GoRoute(path: '/', builder: (_, __) => const ScanScreen()),
            GoRoute(path: '/ref', builder: (_, __) => const ReferenceScreen()),
            GoRoute(path: '/logs', builder: (_, __) => const LogScreen()),
            GoRoute(path: '/stats', builder: (_, __) => const StatsScreen()),
          ],
        ),
      ],
    );

    return MaterialApp.router(
      title: 'CleanPack AR',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(),
      routerConfig: router,
    );
  }
}

class _Shell extends StatelessWidget {
  final Widget child;
  final String location;
  const _Shell({required this.child, required this.location});

  int get _idx {
    if (location.startsWith('/ref')) return 1;
    if (location.startsWith('/logs')) return 2;
    if (location.startsWith('/stats')) return 3;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: _NavBar(index: _idx, onTap: (i) {
        const paths = ['/', '/ref', '/logs', '/stats'];
        context.go(paths[i]);
      }),
    );
  }
}

class _NavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _NavBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.center_focus_strong_rounded, 'Сканер'),
      (Icons.image_outlined, 'Эталон'),
      (Icons.list_alt_rounded, 'Журнал'),
      (Icons.insights_rounded, 'Статистика'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.surface,
        border: const Border(
          top: BorderSide(color: AppPalette.borderSoft),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final active = i == index;
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onTap(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    padding:
                        const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    decoration: BoxDecoration(
                      color: active
                          ? AppPalette.sage.withOpacity(0.15)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(items[i].$1,
                            color: active
                                ? AppPalette.sage
                                : AppPalette.slate,
                            size: 22),
                        const SizedBox(height: 4),
                        Text(items[i].$2,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: active
                                    ? AppPalette.sage
                                    : AppPalette.slate)),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

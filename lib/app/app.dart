import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/system/presentation/providers/system_providers.dart';
import '../features/system/presentation/screens/force_update_screen.dart';
import '../features/system/presentation/screens/maintenance_screen.dart';
import '../shared/providers/core_providers.dart';
import '../shared/providers/settings_provider.dart';
import 'constants/app_constants.dart';
import 'routes/app_router.dart';
import 'theme/app_theme.dart';

/// Root widget: wires the router and theming into [MaterialApp.router].
class VSMartApp extends ConsumerWidget {
  const VSMartApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Lock text scaling to a sane range to protect the design system.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.3,
            ),
          ),
          child: _BootstrapGate(
            child: _OfflineWrap(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
    );
  }
}

/// App-wide offline indicator. A slim strip animates in at the very top (above
/// every screen's app bar) whenever connectivity drops, pushing content down so
/// nothing is obscured — universal offline awareness without per-screen wiring.
class _OfflineWrap extends ConsumerWidget {
  const _OfflineWrap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(connectivityStatusProvider).maybeWhen(
          data: (online) => !online,
          orElse: () => false,
        );
    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: offline
              ? const _OfflineStrip()
              : const SizedBox(width: double.infinity),
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _OfflineStrip extends StatelessWidget {
  const _OfflineStrip();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.error,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 14, color: AppColors.white),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'No internet connection',
                style: AppTypography.labelSmall.copyWith(color: AppColors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// App-wide gate above the router: shows Force-Update / Maintenance over the
/// whole app when the backend (`/app-config`) requires it. Fails OPEN — while
/// the config is loading or unreachable it renders the app normally, so a flaky
/// bootstrap call never blocks usage (per-screen offline handling takes over).
class _BootstrapGate extends ConsumerWidget {
  const _BootstrapGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(appStatusProvider).valueOrNull;
    if (status != null) {
      if (ref.watch(forceUpdateProvider)) return const ForceUpdateScreen();
      if (status.maintenance) {
        return MaintenanceScreen(message: status.maintenanceMessage);
      }
    }
    return child;
  }
}

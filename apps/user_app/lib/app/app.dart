import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/extensions/context_extensions.dart';
import '../core/services/deep_link_controller.dart';
import '../core/services/push_controller.dart';
import '../core/utils/app_logger.dart';
import '../features/auth/presentation/providers/current_user_provider.dart';
import '../features/system/presentation/providers/system_providers.dart';
import '../features/system/presentation/screens/force_update_screen.dart';
import '../features/system/presentation/screens/maintenance_screen.dart';
import '../l10n/generated/app_localizations.dart';
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
    // Selected app language (persisted); drives both the locale and the script
    // font fallbacks. Runtime switching just updates this provider — no logout.
    final localeCode = ref.watch(localeProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: Locale(localeCode),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
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
          child: _DeepLinkGate(
            child: _PushGate(
              child: _BootstrapGate(
                child: _OfflineWrap(child: child ?? const SizedBox.shrink()),
              ),
            ),
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
                context.l10n.commonNoInternet,
                style: AppTypography.labelSmall.copyWith(color: AppColors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Starts deep-link listening for the whole app session.
///
/// Unlike [_PushGate] this is NOT gated on authentication: the link that launched
/// the app arrives before anyone signs in, and it has to be captured then or it's
/// gone. The controller only parks it — the router decides when it's safe to open,
/// which is what lets a shared link survive onboarding and a sign-in.
class _DeepLinkGate extends ConsumerStatefulWidget {
  const _DeepLinkGate({required this.child});

  final Widget child;

  @override
  ConsumerState<_DeepLinkGate> createState() => _DeepLinkGateState();
}

class _DeepLinkGateState extends ConsumerState<_DeepLinkGate> {
  @override
  void initState() {
    super.initState();
    // Post-frame so the router provider is built before a link can be parked.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(deepLinkControllerProvider).start();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Starts push notifications once the user is authenticated: registers the FCM
/// token with the backend and wires foreground display + tap routing. Resets on
/// logout so a re-login re-registers. Transparent — always renders [child].
class _PushGate extends ConsumerStatefulWidget {
  const _PushGate({required this.child});

  final Widget child;

  @override
  ConsumerState<_PushGate> createState() => _PushGateState();
}

class _PushGateState extends ConsumerState<_PushGate> {
  bool _started = false;

  /// Push setup must never be able to break the app.
  ///
  /// This runs from a `ref.listen` on the current user, so it fires in the
  /// middle of the sign-in transition — the same turn the router is computing
  /// its redirect. An exception escaping here propagates *into that redirect*
  /// and dead-ends navigation on the error screen, which is exactly what
  /// happened on a build with no `google-services.json`. Notifications are a
  /// nice-to-have; being able to navigate is not.
  void _onUser(Object? user) {
    try {
      if (user == null) {
        // Logged out: server-side tokens are deactivated by /auth/logout; allow
        // a fresh registration on the next login.
        _started = false;
        ref.read(pushControllerProvider).reset();
        return;
      }
      if (_started) return;
      _started = true;
      ref.read(pushControllerProvider).start();
      // Sync the cached profile with the backend once per session. The session
      // user is a login-time snapshot; flags that change server-side afterwards
      // (creditEnabled, kycStatus) otherwise stay stale until the profile
      // screen's manual pull-to-refresh. Fire-and-forget: on failure the
      // cached user stays in place.
      ref.read(refreshUserProvider.future).ignore();
    } catch (e, st) {
      AppLogger.w('Push gate skipped: $e');
      AppLogger.d(st);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onUser(ref.read(currentUserProvider));
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentUserProvider, (_, next) => _onUser(next));
    return widget.child;
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

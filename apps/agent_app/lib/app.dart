import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/env.dart';
import 'core/navigation.dart';
import 'core/providers.dart';
import 'core/services/presence_controller.dart';
import 'core/services/push_controller.dart';
import 'core/ui.dart';
import 'features/auth/login_screen.dart';
import 'features/dashboard/presentation/dashboard_providers.dart';
import 'features/home/home_shell.dart';
import 'features/onboarding/presentation/face_capture_screen.dart';
import 'features/splash/splash_screen.dart';

class AgentApp extends StatelessWidget {
  const AgentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Env.appName,
      debugShowCheckedModeBanner: false,
      theme: buildAgentTheme(),
      navigatorKey: rootNavigatorKey,
      builder: (context, child) => _PushGate(child: child ?? const SizedBox()),
      home: const _AuthGate(),
    );
  }
}

/// Starts the push orchestrator once the agent is authenticated (registers the
/// FCM device token, foreground display, tap deep-linking) and resets it on
/// logout so a re-login re-registers. Wrapping the whole app means the gate
/// survives across the login → shell transition. No-op without Firebase config.
class _PushGate extends ConsumerStatefulWidget {
  const _PushGate({required this.child});

  final Widget child;

  @override
  ConsumerState<_PushGate> createState() => _PushGateState();
}

class _PushGateState extends ConsumerState<_PushGate> {
  @override
  Widget build(BuildContext context) {
    // authStatusProvider starts at `unknown`, then resolves to authenticated /
    // unauthenticated once the token store is read — so the boot-time
    // already-logged-in case arrives here as an unknown→authenticated
    // transition. start()/reset() are both idempotent.
    ref.listen<AuthStatus>(authStatusProvider, (prev, next) {
      final controller = ref.read(pushControllerProvider);
      if (next == AuthStatus.authenticated) {
        controller.start();
      } else if (next == AuthStatus.unauthenticated) {
        controller.reset();
        // A signed-out device must not keep pinging a location for the
        // account that just logged off.
        ref.read(presenceControllerProvider).stop();
      }
    });
    return widget.child;
  }
}

/// Shows the login screen, a one-time face-capture step, or the agent shell
/// based on auth state. `_dismissedThisSession` is in-memory only (not
/// persisted) — skipping gets an agent into the app for this session without
/// blocking them, but they see the prompt again on their next cold start
/// until a photo actually uploads (i.e. until `avatarUrl` is no longer empty).
class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate> {
  bool _dismissedThisSession = false;

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(authStatusProvider);
    if (status == AuthStatus.unknown) return const AgentSplashScreen();
    if (status == AuthStatus.unauthenticated) return const LoginScreen();

    if (!_dismissedThisSession) {
      final profile = ref.watch(agentProfileProvider).valueOrNull;
      // Still loading the profile — stay on a blank loader rather than flash
      // the capture screen for a profile that turns out to already have a
      // photo (avoided by simply not deciding yet).
      if (profile == null) return const Scaffold(body: Loading());
      if (!profile.hasAvatar) {
        return FaceCaptureScreen(
          onDone: () => setState(() => _dismissedThisSession = true),
        );
      }
    }
    return const HomeShell();
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/extensions/context_extensions.dart';
import '../../core/widgets/widgets.dart';
import '../../features/cart/presentation/providers/cart_providers.dart';
import '../../features/serviceability/presentation/providers/serviceability_gate_providers.dart';

/// Hosts the persistent bottom navigation for the main authenticated tabs and
/// renders the active [StatefulNavigationShell] branch.
///
/// Back handling: a pushed/nested route pops normally; from a non-Home tab root
/// back switches to Home; from Home it requires a second press within 2s to
/// exit (with a "press back again" toast).
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  DateTime? _lastBackAt;

  @override
  void initState() {
    super.initState();
    // Kick off the once-per-session GPS serviceability hard-lock check the
    // moment the authenticated shell mounts. Idempotent — the lock screen fires
    // the same call, whichever mounts first wins.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(serviceabilityGateProvider.notifier).ensureChecked();
    });
  }

  void _onTap(int index) {
    widget.navigationShell.goBranch(
      index,
      // Re-tapping the active tab pops to its root.
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  void _handleBack() {
    final router = GoRouter.of(context);
    // Let any nested/branch route pop first (e.g. credit sub-screens).
    if (router.canPop()) {
      router.pop();
      return;
    }
    // At a tab root: a non-Home tab returns to Home first.
    if (widget.navigationShell.currentIndex != 0) {
      _onTap(0);
      return;
    }
    // Home root: double-press to exit.
    final now = DateTime.now();
    if (_lastBackAt != null &&
        now.difference(_lastBackAt!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    context.showSnack('Press back again to exit');
  }

  @override
  Widget build(BuildContext context) {
    final cartCount = ref.watch(cartItemCountProvider);
    final items = <VSNavItem>[
      const VSNavItem(asset: 'assets/icons/nav_home.svg', label: 'Home'),
      const VSNavItem(
          asset: 'assets/icons/nav_categories.svg', label: 'Categories'),
      VSNavItem(
        asset: 'assets/icons/nav_cart.svg',
        label: 'Cart',
        isCart: true,
        badgeCount: cartCount,
      ),
      const VSNavItem(asset: 'assets/icons/nav_credit.svg', label: 'Credit'),
      const VSNavItem(asset: 'assets/icons/nav_profile.svg', label: 'Profile'),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        body: widget.navigationShell,
        bottomNavigationBar: VSBottomNavigation(
          items: items,
          currentIndex: widget.navigationShell.currentIndex,
          onTap: _onTap,
        ),
      ),
    );
  }
}

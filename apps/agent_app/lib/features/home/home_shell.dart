import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/services/task_sync.dart';
import '../../core/ui.dart';
import '../collections/presentation/collections_screen.dart';
import '../dashboard/presentation/dashboard_screen.dart';
import '../deliveries/presentation/deliveries_screen.dart';
import '../profile/presentation/profile_screen.dart';
import '../verification/presentation/verify_screen.dart';

/// Authenticated agent shell with the Figma 5-tab bottom bar:
/// Home · Collections · Deliveries · Tasks · Profile. The active tab renders as a
/// green pill (design system). "Tasks" hosts the field-verification + KYC queue.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  static const _screens = [
    DashboardScreen(),
    CollectionsScreen(),
    DeliveriesScreen(),
    VerifyScreen(),
    ProfileScreen(),
  ];

  /// Every tab lives in an IndexedStack, so its providers never auto-dispose
  /// and would otherwise serve their launch-time snapshot for the whole
  /// session. [TaskSync] is what keeps newly-assigned work appearing.
  late final TaskSync _sync;

  DateTime? _lastBackAt;

  /// The sequence of tabs actually visited, oldest first — always starts at
  /// Home (index 0) and never empties, so there's always something to fall
  /// back to. Back pops the tab just switched TO, landing on whichever tab
  /// was open before it — real history, not a straight jump to Home.
  final List<int> _tabHistory = [0];

  @override
  void initState() {
    super.initState();
    _sync = ref.read(taskSyncProvider)..start();
  }

  /// Record a tab switch in the history, unless it's a no-op (re-tapping the
  /// already-active tab).
  void _goToTab(int index) {
    if (_tabHistory.last == index) return;
    _tabHistory.add(index);
    ref.read(homeTabProvider.notifier).state = index;
    // Switching to a queue is an explicit "show me what's there now" —
    // refetch rather than showing a stale list.
    _sync.refreshNow();
  }

  /// Tabs switch by changing [homeTabProvider]'s index into an IndexedStack —
  /// there's no route push for the system back button to pop, so with no
  /// handling at all it fell straight through to exiting the app from ANY
  /// tab, home or not. Back now walks [_tabHistory] one step at a time —
  /// Home → Collections → Deliveries steps back to Collections, then Home —
  /// rather than jumping straight to Home from wherever you are. Only once
  /// the history is down to just Home does back mean "exit," and even then
  /// only on a double-press, so a stray back button doesn't kill the app out
  /// from under an on-duty agent.
  void _handleBack() {
    if (_tabHistory.length > 1) {
      _tabHistory.removeLast();
      ref.read(homeTabProvider.notifier).state = _tabHistory.last;
      return;
    }
    final now = DateTime.now();
    if (_lastBackAt != null &&
        now.difference(_lastBackAt!) < const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackAt = now;
    showToast(context, 'Press back again to exit');
  }

  static const _tabs = [
    (icon: Icons.home_rounded, label: 'Home'),
    (icon: Icons.account_balance_wallet_rounded, label: 'Collections'),
    (icon: Icons.local_shipping_rounded, label: 'Deliveries'),
    (icon: Icons.verified_user_rounded, label: 'Verify'),
    (icon: Icons.person_rounded, label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(homeTabProvider);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        body: IndexedStack(index: index, children: _screens),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: AgentColors.bg,
            border: Border(top: BorderSide(color: AgentColors.divider)),
            boxShadow: [
              BoxShadow(
                color: Color(0x1A000000),
                blurRadius: 15,
                offset: Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 65,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var i = 0; i < _tabs.length; i++)
                    _NavItem(
                      icon: _tabs[i].icon,
                      label: _tabs[i].label,
                      active: index == i,
                      onTap: () => _goToTab(i),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AgentColors.brandBright : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: active ? Colors.white : AgentColors.label,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
                color: active ? Colors.white : AgentColors.label,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/constants/app_constants.dart';
import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/extensions/num_extensions.dart';
import '../../../../core/extensions/string_extensions.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../address/domain/entities/address.dart';
import '../../../address/presentation/providers/address_providers.dart';
import '../../../auth/domain/entities/user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/providers/current_user_provider.dart';
import '../../../billing/domain/entities/billing_enums.dart';
import '../../../billing/domain/entities/repayment.dart';
import '../../../billing/presentation/providers/billing_providers.dart';
import '../../../credit/domain/credit_access.dart';
import '../../../credit/domain/entities/credit_account.dart';
import '../../../credit/presentation/providers/credit_access_provider.dart';
import '../../../credit/presentation/providers/credit_providers.dart';
import '../../../credit/presentation/widgets/credit_apply_card.dart';
import '../../../orders/domain/entities/order.dart';
import '../../../orders/domain/entities/order_enums.dart';
import '../../../orders/presentation/providers/order_providers.dart';

/// The Profile tab — the customer hub. Built to match the "Profile Commerce
/// Dashboard" design: profile summary, available-credit card, recent orders,
/// a quick-action grid, credit center, address preview, recent payments, KYC
/// status, offers and the support/settings list.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(analyticsServiceProvider).track('account_viewed');
    });
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to sign in again to access your account.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    ref.read(analyticsServiceProvider).track('logout');
    await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final access = ref.watch(creditAccessProvider);
    // Only fetch / show real credit figures for an active account — no leak.
    final account = access.isActive
        ? ref.watch(creditAccountProvider).valueOrNull
        : null;
    final orders = ref.watch(ordersProvider).valueOrNull ?? const <Order>[];
    final address = ref.watch(defaultAddressProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => context.pushNamed(RouteNames.settings),
        ),
        title: Text('Profile', style: AppTypography.headlineSmall),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.pushNamed(RouteNames.settings),
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none_rounded),
            tooltip: 'Notifications',
            onPressed: () => context.pushNamed(RouteNames.notifications),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xxl),
          children: [
            if (user == null) ...[
              const _GuestSignInCard(),
              AppSpacing.vGapMd,
            ],
            _ProfileTopCard(
                user: user, account: account, showCredit: access.isActive),
            AppSpacing.vGapMd,
            if (access.isActive)
              _AvailableCreditCard(
                account: account,
                onViewStatement: () =>
                    context.pushNamed(RouteNames.statements),
                onPayDue: () => context.pushNamed(RouteNames.repayment),
              )
            else
              CreditApplyCard(access: access),
            AppSpacing.vGapMd,
            _RecentOrdersCard(orders: orders),
            AppSpacing.vGapMd,
            const _QuickGrid(),
            AppSpacing.vGapMd,
            if (access.isActive) ...[
              const _CreditCenterCard(),
              AppSpacing.vGapMd,
            ],
            _AddressPreviewCard(address: address),
            AppSpacing.vGapMd,
            const _RecentPaymentsCard(),
            AppSpacing.vGapMd,
            _KycStatusCard(user: user),
            AppSpacing.vGapMd,
            const _OffersRewardsCard(),
            AppSpacing.vGapMd,
            const _SupportSettingsCard(),
            AppSpacing.vGapMd,
            if (user != null) ...[
              OutlinedButton.icon(
                onPressed: _confirmLogout,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side:
                      BorderSide(color: AppColors.error.withValues(alpha: 0.5)),
                  minimumSize: const Size.fromHeight(50),
                ),
                icon: const Icon(Icons.logout_rounded, size: 20),
                label: const Text('Log Out'),
              ),
              AppSpacing.vGapMd,
            ],
            Center(
              child: Text(
                '${AppConstants.appName} · Version 1.0.0',
                style: AppTypography.labelSmall
                    .copyWith(color: context.vsColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// White rounded card wrapper used by every section on the dashboard.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: AppRadius.brLg,
        border: Border.all(color: context.vsColors.border),
      ),
      child: child,
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: AppTypography.titleLarge),
        if (actionLabel != null)
          GestureDetector(
            onTap: onAction,
            child: Text(actionLabel!,
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.trustBlue)),
          ),
      ],
    );
  }
}

/// Shown on the Account tab when browsing as a guest — invites sign-in/sign-up.
class _GuestSignInCard extends StatelessWidget {
  const _GuestSignInCard();

  @override
  Widget build(BuildContext context) {
    final faint = AppColors.white.withValues(alpha: 0.9);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        gradient: AppColors.greenGradient,
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline_rounded,
                  color: AppColors.white, size: 22),
              AppSpacing.hGapSm,
              Text("You're browsing as a guest",
                  style: AppTypography.titleLarge
                      .copyWith(color: AppColors.white)),
            ],
          ),
          AppSpacing.vGapSm,
          Text(
            'Sign in to place orders, track deliveries and unlock VS Credit.',
            style: AppTypography.bodySmall.copyWith(color: faint),
          ),
          AppSpacing.vGapMd,
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.pushNamed(RouteNames.login),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.white,
                foregroundColor: AppColors.vsGreen,
                elevation: 0,
                minimumSize: const Size.fromHeight(46),
                shape:
                    const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
              ),
              child: Text('Sign in / Create account',
                  style: AppTypography.labelLarge
                      .copyWith(color: AppColors.vsGreen)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTopCard extends StatelessWidget {
  const _ProfileTopCard({
    required this.user,
    required this.account,
    this.showCredit = true,
  });

  final User? user;
  final CreditAccount? account;
  final bool showCredit;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final name = (user?.name).isNullOrBlank ? 'Guest' : user!.name;
    final memberId = (user?.id).isNullOrBlank ? '—' : user!.id;
    return _Card(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: vs.brandTint,
              borderRadius: AppRadius.brMd,
            ),
            child: Text(
              name.initials.isEmpty ? '?' : name.initials,
              style: AppTypography.titleLarge.copyWith(color: vs.brand),
            ),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.titleLarge),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.verified_rounded, size: 16, color: vs.success),
                  ],
                ),
                Text(memberId,
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
          ),
          if (showCredit) ...[
            AppSpacing.hGapMd,
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('Credit ${(account?.available ?? 0).asCurrencyCompact}',
                    style: AppTypography.labelMedium),
                Text('Score ${account?.vsScore ?? '—'}',
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _AvailableCreditCard extends StatelessWidget {
  const _AvailableCreditCard({
    required this.account,
    required this.onViewStatement,
    required this.onPayDue,
  });

  final CreditAccount? account;
  final VoidCallback onViewStatement;
  final VoidCallback onPayDue;

  static const _gradient = LinearGradient(
    colors: [AppColors.vsGreen, AppColors.trustBlue],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  @override
  Widget build(BuildContext context) {
    final faint = AppColors.white.withValues(alpha: 0.85);
    final available = account?.available ?? 0;
    final used = account?.outstanding ?? 0;
    final limit = account?.creditLimit ?? 0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        gradient: _gradient,
        borderRadius: AppRadius.brLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AVAILABLE CREDIT',
                        style: AppTypography.labelSmall
                            .copyWith(color: faint, letterSpacing: 0.5)),
                    AppSpacing.vGapXs,
                    Text(available.asCurrency,
                        style: AppTypography.displayMedium
                            .copyWith(color: AppColors.white)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.white.withValues(alpha: 0.18),
                  borderRadius: AppRadius.brMd,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.speed_rounded,
                            size: 14, color: AppColors.white),
                        const SizedBox(width: 4),
                        Text('VS Score',
                            style: AppTypography.labelSmall
                                .copyWith(color: faint)),
                      ],
                    ),
                    Text('${account?.vsScore ?? '—'}',
                        style: AppTypography.titleLarge
                            .copyWith(color: AppColors.white)),
                  ],
                ),
              ),
            ],
          ),
          AppSpacing.vGapMd,
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Used: ${used.asCurrency}',
                  style: AppTypography.bodySmall.copyWith(color: faint)),
              Text('Limit: ${limit.asCurrency}',
                  style: AppTypography.bodySmall.copyWith(color: faint)),
            ],
          ),
          AppSpacing.vGapMd,
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onViewStatement,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.white.withValues(alpha: 0.18),
                    foregroundColor: AppColors.white,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(44),
                    shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.brMd),
                  ),
                  child: Text('View Statement',
                      style: AppTypography.labelMedium
                          .copyWith(color: AppColors.white)),
                ),
              ),
              AppSpacing.hGapMd,
              Expanded(
                child: FilledButton(
                  onPressed: onPayDue,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.white,
                    foregroundColor: AppColors.trustBlue,
                    elevation: 0,
                    minimumSize: const Size.fromHeight(44),
                    shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.brMd),
                  ),
                  child: Text('Pay Due',
                      style: AppTypography.labelMedium
                          .copyWith(color: AppColors.trustBlue)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecentOrdersCard extends StatelessWidget {
  const _RecentOrdersCard({required this.orders});

  final List<Order> orders;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final recent = orders.take(2).toList();
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            title: 'Recent Orders',
            actionLabel: 'View All',
            onAction: () => context.pushNamed(RouteNames.orders),
          ),
          AppSpacing.vGapMd,
          if (recent.isEmpty)
            Text('No orders yet.',
                style:
                    AppTypography.bodyMedium.copyWith(color: vs.textSecondary))
          else
            for (var i = 0; i < recent.length; i++) ...[
              if (i != 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Divider(height: 1, color: vs.border),
                ),
              _OrderRow(order: recent[i]),
            ],
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final delivered = order.status == OrderStatus.delivered;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Order #${order.id}', style: AppTypography.titleMedium),
              AppSpacing.vGapXs,
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: delivered ? vs.success : vs.warning,
                      shape: BoxShape.circle,
                    ),
                  ),
                  AppSpacing.hGapSm,
                  Text(
                    '${order.status.label} · ${order.summary.grandTotal.asCurrency}',
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
        OutlinedButton(
          onPressed: () => context.pushNamed(
            RouteNames.orderDetails,
            pathParameters: {'orderId': order.id},
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: vs.brand,
            side: BorderSide(color: vs.brand),
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
          ),
          child: Text('Reorder',
              style: AppTypography.labelSmall.copyWith(color: vs.brand)),
        ),
      ],
    );
  }
}

class _QuickGrid extends StatelessWidget {
  const _QuickGrid();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final items = <_QuickItem>[
      _QuickItem(Icons.receipt_long_outlined, 'My Orders', vs.brand,
          () => context.pushNamed(RouteNames.orders)),
      _QuickItem(Icons.description_outlined, 'Statements', vs.trust,
          () => context.pushNamed(RouteNames.statements)),
      _QuickItem(Icons.payments_outlined, 'Payments', vs.brand,
          () => context.pushNamed(RouteNames.paymentHistory)),
      _QuickItem(Icons.location_on_outlined, 'Addresses', vs.offer,
          () => context.pushNamed(RouteNames.addresses)),
      _QuickItem(Icons.favorite_border_rounded, 'Wishlist', AppColors.error,
          () => context.pushNamed(RouteNames.wishlist)),
      _QuickItem(Icons.local_offer_outlined, 'Offers', vs.offer,
          () => context.pushNamed(RouteNames.offers)),
      _QuickItem(Icons.notifications_none_rounded, 'Alerts', vs.trust,
          () => context.pushNamed(RouteNames.notifications)),
      _QuickItem(Icons.headset_mic_outlined, 'Support', vs.brand,
          () => context.pushNamed(RouteNames.support)),
    ];
    return _Card(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
      child: GridView.count(
        crossAxisCount: 4,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.xs,
        childAspectRatio: 1.05,
        children: [for (final i in items) _QuickTile(item: i)],
      ),
    );
  }
}

class _QuickItem {
  const _QuickItem(this.icon, this.label, this.color, this.onTap);
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.item});

  final _QuickItem item;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: AppRadius.brMd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.12),
              borderRadius: AppRadius.brSm,
            ),
            child: Icon(item.icon, size: 16, color: item.color),
          ),
          const SizedBox(height: 3),
          Text(item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(fontSize: 9.5)),
        ],
      ),
    );
  }
}

class _CreditCenterCard extends StatelessWidget {
  const _CreditCenterCard();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final rows = <(IconData, String, Color, String)>[
      (Icons.description_outlined, 'Monthly Statement', vs.brand,
          RouteNames.statements),
      (Icons.account_balance_wallet_outlined, 'Outstanding Due', AppColors.error,
          RouteNames.outstandingDue),
      (Icons.bar_chart_rounded, 'Credit Usage', vs.trust,
          RouteNames.paymentHistory),
      (Icons.speed_rounded, 'VS Score Details', vs.offer,
          RouteNames.creditDashboard),
    ];
    return _Card(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Credit Center', style: AppTypography.titleLarge),
          AppSpacing.vGapSm,
          for (final (icon, label, color, route) in rows)
            _ListRow(
              icon: icon,
              label: label,
              color: color,
              onTap: () => route == RouteNames.creditDashboard
                  ? context.goNamed(route)
                  : context.pushNamed(route),
            ),
        ],
      ),
    );
  }
}

/// A tappable list row: tinted icon, label, trailing chevron.
class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    final c = color ?? vs.brand;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.brSm,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.withValues(alpha: 0.12),
                borderRadius: AppRadius.brSm,
              ),
              child: Icon(icon, size: 20, color: c),
            ),
            AppSpacing.hGapMd,
            Expanded(child: Text(label, style: AppTypography.bodyLarge)),
            Icon(Icons.chevron_right_rounded, color: vs.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _AddressPreviewCard extends StatelessWidget {
  const _AddressPreviewCard({required this.address});

  final Address? address;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.home_rounded, size: 18, color: vs.brand),
              AppSpacing.hGapSm,
              Text('Home', style: AppTypography.titleMedium),
              const Spacer(),
              GestureDetector(
                onTap: () => context.pushNamed(RouteNames.addresses),
                child: Text('Edit',
                    style: AppTypography.labelMedium
                        .copyWith(color: AppColors.trustBlue)),
              ),
            ],
          ),
          AppSpacing.vGapSm,
          Text(
            address?.formatted ?? 'No saved address yet.',
            style: AppTypography.bodySmall.copyWith(color: vs.textSecondary),
          ),
          AppSpacing.vGapMd,
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.pushNamed(RouteNames.addresses),
              style: FilledButton.styleFrom(
                backgroundColor: vs.brandTint,
                foregroundColor: vs.brand,
                elevation: 0,
                minimumSize: const Size.fromHeight(44),
                shape:
                    const RoundedRectangleBorder(borderRadius: AppRadius.brMd),
              ),
              child: Text('Manage Addresses',
                  style: AppTypography.labelMedium.copyWith(color: vs.brand)),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentPaymentsCard extends ConsumerWidget {
  const _RecentPaymentsCard();

  static const _months = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  ({IconData icon, String label}) _method(RepaymentMethod m) => switch (m) {
        RepaymentMethod.upi => (icon: Icons.account_balance_rounded, label: 'UPI Payment'),
        RepaymentMethod.card => (icon: Icons.credit_card_rounded, label: 'Card Payment'),
        RepaymentMethod.bankTransfer =>
          (icon: Icons.account_balance_outlined, label: 'Bank Transfer'),
        RepaymentMethod.cashCollection =>
          (icon: Icons.local_atm_rounded, label: 'Cash Collection'),
      };

  String _fmt(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final min = d.minute.toString().padLeft(2, '0');
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '${d.day} ${_months[d.month]} ${d.year} · $h:$min $ampm';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vs = context.vsColors;
    final paymentsAsync = ref.watch(paymentHistoryProvider);
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            title: 'Recent Payments',
            actionLabel: 'View History',
            onAction: () => context.pushNamed(RouteNames.paymentHistory),
          ),
          AppSpacing.vGapSm,
          paymentsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text('Could not load payments.',
                  style: AppTypography.bodySmall
                      .copyWith(color: vs.textSecondary)),
            ),
            data: (payments) {
              if (payments.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Text('No payments yet.',
                      style: AppTypography.bodySmall
                          .copyWith(color: vs.textSecondary)),
                );
              }
              final recent = payments.take(3).toList();
              return Column(
                children: [
                  for (final Repayment p in recent)
                    _PaymentRow(
                      data: _method(p.method),
                      subtitle: _fmt(p.date),
                      amount: '+${p.amount.asCurrency}',
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.data,
    required this.subtitle,
    required this.amount,
  });

  final ({IconData icon, String label}) data;
  final String subtitle;
  final String amount;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: vs.trustTint,
              borderRadius: AppRadius.brSm,
            ),
            child: Icon(data.icon, size: 18, color: vs.trust),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(data.label, style: AppTypography.titleMedium),
                Text(subtitle,
                    style: AppTypography.labelSmall
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
          ),
          Text(amount,
              style: AppTypography.labelLarge.copyWith(color: vs.success)),
        ],
      ),
    );
  }
}

class _KycStatusCard extends StatelessWidget {
  const _KycStatusCard({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    final verified = user?.isKycVerified ?? false;
    final items = ['Aadhaar', 'PAN Card', 'Selfie', 'House Verification'];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('KYC Status', style: AppTypography.titleLarge),
          AppSpacing.vGapMd,
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 4.5,
            mainAxisSpacing: AppSpacing.sm,
            crossAxisSpacing: AppSpacing.lg,
            children: [
              for (final item in items)
                _KycRow(label: item, done: verified),
            ],
          ),
        ],
      ),
    );
  }
}

class _KycRow extends StatelessWidget {
  const _KycRow({required this.label, required this.done});

  final String label;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return Row(
      children: [
        Icon(
          done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          size: 18,
          color: done ? vs.success : vs.textSecondary,
        ),
        AppSpacing.hGapSm,
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodyMedium),
        ),
      ],
    );
  }
}

class _OffersRewardsCard extends StatelessWidget {
  const _OffersRewardsCard();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return _Card(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: vs.offerTint,
              borderRadius: AppRadius.brMd,
            ),
            child: Icon(Icons.card_giftcard_rounded, color: vs.offer),
          ),
          AppSpacing.hGapMd,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Offers & Rewards', style: AppTypography.titleMedium),
                Text('3 Active Coupons',
                    style: AppTypography.bodySmall
                        .copyWith(color: vs.textSecondary)),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => context.pushNamed(RouteNames.coupons),
            style: OutlinedButton.styleFrom(
              foregroundColor: vs.brand,
              side: BorderSide(color: vs.brand),
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              shape: const RoundedRectangleBorder(borderRadius: AppRadius.brSm),
            ),
            child: Text('View Offers',
                style: AppTypography.labelSmall.copyWith(color: vs.brand)),
          ),
        ],
      ),
    );
  }
}

class _SupportSettingsCard extends StatelessWidget {
  const _SupportSettingsCard();

  @override
  Widget build(BuildContext context) {
    final vs = context.vsColors;
    return _Card(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: Column(
        children: [
          _ListRow(
            icon: Icons.help_outline_rounded,
            label: 'FAQ & Help',
            color: vs.trust,
            onTap: () => context.pushNamed(RouteNames.faq),
          ),
          Divider(height: 1, color: vs.border),
          _ListRow(
            icon: Icons.headset_mic_outlined,
            label: 'Contact Support',
            color: vs.brand,
            onTap: () => context.pushNamed(RouteNames.support),
          ),
          Divider(height: 1, color: vs.border),
          _ListRow(
            icon: Icons.stars_rounded,
            label: 'Rewards',
            color: vs.offer,
            onTap: () => context.pushNamed(RouteNames.rewards),
          ),
          Divider(height: 1, color: vs.border),
          _ListRow(
            icon: Icons.assignment_return_outlined,
            label: 'My Returns',
            color: vs.trust,
            onTap: () => context.pushNamed(RouteNames.returns),
          ),
          Divider(height: 1, color: vs.border),
          _ListRow(
            icon: Icons.card_giftcard_rounded,
            label: 'Refer & Earn',
            color: vs.offer,
            onTap: () => context.pushNamed(RouteNames.referEarn),
          ),
          Divider(height: 1, color: vs.border),
          _ListRow(
            icon: Icons.language_rounded,
            label: 'Language (English)',
            color: vs.offer,
            onTap: () => context.pushNamed(RouteNames.language),
          ),
          Divider(height: 1, color: vs.border),
          _ListRow(
            icon: Icons.info_outline_rounded,
            label: 'About VS Mart',
            color: vs.textSecondary,
            onTap: () => context.pushNamed(RouteNames.about),
          ),
          Divider(height: 1, color: vs.border),
          _ListRow(
            icon: Icons.mail_outline_rounded,
            label: 'Contact Us',
            color: vs.textSecondary,
            onTap: () => context.pushNamed(RouteNames.contact),
          ),
          Divider(height: 1, color: vs.border),
          _ListRow(
            icon: Icons.work_outline_rounded,
            label: 'Careers',
            color: vs.textSecondary,
            onTap: () => context.pushNamed(RouteNames.careers),
          ),
          Divider(height: 1, color: vs.border),
          _ListRow(
            icon: Icons.privacy_tip_outlined,
            label: 'Privacy Policy',
            color: vs.textSecondary,
            onTap: () => context.pushNamed(RouteNames.privacyPolicy),
          ),
        ],
      ),
    );
  }
}

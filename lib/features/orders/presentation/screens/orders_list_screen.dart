import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../app/routes/route_paths.dart';
import '../../../../app/theme/app_theme.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/widgets/widgets.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../cart/domain/entities/cart_item.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/order_enums.dart';
import '../providers/order_providers.dart';
import '../widgets/order_widgets.dart';

/// Orders history with Active / Completed / Cancelled tabs.
class OrdersListScreen extends ConsumerWidget {
  const OrdersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectivity = ref.watch(commerceConnectivityProvider);
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My Orders'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Active'),
              Tab(text: 'Completed'),
              Tab(text: 'Cancelled'),
            ],
          ),
        ),
        body: Column(
          children: [
            VSOfflineBanner(
              offline: connectivity == CommerceConnectivity.offline,
              syncing: connectivity == CommerceConnectivity.syncing,
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  _OrdersTab(filter: _ActiveFilter()),
                  _OrdersTab(filter: _CompletedFilter()),
                  _OrdersTab(filter: _CancelledFilter()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

abstract class _Filter {
  const _Filter();
  bool matches(Order o);
  String get emptyMessage;
}

class _ActiveFilter extends _Filter {
  const _ActiveFilter();
  @override
  bool matches(Order o) => o.status.isActive;
  @override
  String get emptyMessage => 'No active orders right now.';
}

class _CompletedFilter extends _Filter {
  const _CompletedFilter();
  @override
  bool matches(Order o) => o.status.isCompleted;
  @override
  String get emptyMessage => 'No completed orders yet.';
}

class _CancelledFilter extends _Filter {
  const _CancelledFilter();
  @override
  bool matches(Order o) => o.status.isCancelled;
  @override
  String get emptyMessage => 'No cancelled orders.';
}

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab({required this.filter});

  final _Filter filter;

  void _reorder(WidgetRef ref, BuildContext context, Order order) {
    final cart = ref.read(cartControllerProvider.notifier);
    for (final item in order.items) {
      cart.add(CartItem(
        productId: item.productId,
        name: item.name,
        brand: item.brand,
        unit: item.unit,
        price: item.price,
        mrp: item.mrp ?? item.price,
        quantity: item.quantity,
        imageUrl: item.imageUrl,
      ));
    }
    context.goNamed(RouteNames.cart);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(ordersProvider);
    return ordersAsync.when(
      loading: () => const VSLoadingView(),
      error: (e, _) => VSErrorView(
        failure: e is Failure ? e : null,
        onRetry: () => ref.invalidate(ordersProvider),
      ),
      data: (orders) {
        final filtered = orders.where(filter.matches).toList();
        if (filtered.isEmpty) {
          return VSEmptyState(
            title: 'Nothing here',
            message: filter.emptyMessage,
            icon: Icons.receipt_long_outlined,
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(ordersProvider),
          child: ListView.separated(
            padding: AppSpacing.screen,
            itemCount: filtered.length,
            separatorBuilder: (_, __) => AppSpacing.vGapMd,
            itemBuilder: (_, i) {
              final order = filtered[i];
              return VSOrderCard(
                orderId: order.id,
                statusLabel: order.status.label,
                statusTone: orderStatusTone(order.status),
                total: order.summary.grandTotal,
                itemCount: order.itemCount,
                dateLabel: DateFormat('d MMM yyyy').format(order.placedAt),
                thumbnailUrls: [
                  for (final it in order.items)
                    if (it.imageUrl != null) it.imageUrl!,
                ],
                onTap: () => context.pushNamed(
                  RouteNames.orderDetails,
                  pathParameters: {'orderId': order.id},
                ),
                onTrack: order.status.isActive
                    ? () => context.pushNamed(
                          RouteNames.orderTracking,
                          pathParameters: {'orderId': order.id},
                        )
                    : null,
                onReorder: order.status.isCompleted
                    ? () => _reorder(ref, context, order)
                    : null,
              );
            },
          ),
        );
      },
    );
  }
}

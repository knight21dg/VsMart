import 'package:dartz/dartz.dart' hide Order;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../catalog/domain/entities/product.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../data/datasources/order_remote_datasource.dart';
import '../../data/repositories/order_repository_impl.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/order_feedback.dart';
import '../../domain/entities/order_tracking.dart';
import '../../domain/entities/reorder_line.dart';
import '../../domain/repositories/order_repository.dart';

T _unwrap<T>(Either<Failure, T> either) =>
    either.fold((f) => throw f, (value) => value);

/// Exposed on its own because order FEEDBACK is a thin, order-scoped call that
/// doesn't belong behind the repository's Either/Failure contract.
final orderRemoteDataSourceProvider = Provider<OrderRemoteDataSource>(
  (ref) => OrderRemoteDataSource(ref.watch(apiClientProvider)),
);

final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => OrderRepositoryImpl(
    remote: ref.watch(orderRemoteDataSourceProvider),
    hive: ref.watch(hiveServiceProvider),
    networkInfo: ref.watch(networkInfoProvider),
  ),
);

final ordersProvider = FutureProvider<List<Order>>(
  (ref) async => _unwrap(await ref.watch(orderRepositoryProvider).getOrders()),
);

final orderByIdProvider = FutureProvider.family<Order, String>(
  (ref, id) async =>
      _unwrap(await ref.watch(orderRepositoryProvider).getOrderById(id)),
);

/// What reordering an order would add. Read-only: the app applies the result to
/// its LOCAL cart rather than calling `POST /orders/<code>/reorder`, because this
/// client's cart is local and pushed wholesale at checkout — a server-side add
/// would simply be erased by that PUT.
final reorderPreviewProvider =
    FutureProvider.autoDispose.family<ReorderPlan, String>(
  (ref, code) async =>
      _unwrap(await ref.watch(orderRepositoryProvider).reorderPreview(code)),
);

final orderTrackingProvider = FutureProvider.family<OrderTracking, String>(
  (ref, id) async =>
      _unwrap(await ref.watch(orderRepositoryProvider).getTracking(id)),
);

/// Products from the customer's order history — powers the Home "Recently
/// Ordered" rail.
final recentlyOrderedProductsProvider = FutureProvider<List<Product>>((ref) async {
  final orders = await ref.watch(ordersProvider.future);
  final ids = <String>{};
  for (final order in orders) {
    for (final item in order.items) {
      ids.add(item.productId);
    }
  }
  if (ids.isEmpty) return const [];
  final repo = ref.watch(catalogRepositoryProvider);
  final products = <Product>[];
  for (final id in ids.take(8)) {
    (await repo.getProductById(id)).fold((_) {}, products.add);
  }
  return products;
});

/// Frequently-purchased recommendations derived from order history (ranked by
/// total quantity bought). Powers Home / Product Detail / Cart suggestions.
final orderRecommendationProvider = FutureProvider<List<Product>>((ref) async {
  final orders = await ref.watch(ordersProvider.future);
  final frequency = <String, int>{};
  for (final order in orders) {
    for (final item in order.items) {
      frequency[item.productId] =
          (frequency[item.productId] ?? 0) + item.quantity;
    }
  }
  if (frequency.isEmpty) return const [];
  final ranked = frequency.keys.toList()
    ..sort((a, b) => frequency[b]!.compareTo(frequency[a]!));
  final repo = ref.watch(catalogRepositoryProvider);
  final products = <Product>[];
  for (final id in ranked.take(8)) {
    (await repo.getProductById(id)).fold((_) {}, products.add);
  }
  return products;
});

/// Feedback state for one order. `available` is false until the delivery
/// completes and the backend raises the request.
final orderFeedbackProvider =
    FutureProvider.family<OrderFeedback, String>((ref, code) async {
  try {
    return await ref.watch(orderRemoteDataSourceProvider).getFeedback(code);
  } catch (_) {
    // Feedback is a nicety — never let it break the order screen.
    return const OrderFeedback.unavailable();
  }
});

import 'package:dartz/dartz.dart' hide Order;

import '../../../cart/domain/entities/cart_item.dart';
import '../../../../core/errors/failures.dart';
import '../entities/order.dart';
import '../entities/order_enums.dart';
import '../entities/order_tracking.dart';

/// Order pipeline operations. Backed by the backend (`/api/v1`) with a local Hive
/// cache mirror so history/tracking stay readable offline.
abstract interface class OrderRepository {
  /// Sync the local [items] to the server cart and place the order via the
  /// backend checkout (server builds it + reserves stock). Idempotent on
  /// [idempotencyKey]. Returns the confirmed order.
  Future<Either<Failure, Order>> checkout({
    required List<CartItem> items,
    required String addressId,
    required PaymentMethod method,
    required String idempotencyKey,
    String? couponCode,
    String deliverySlot,
    String? creditPlan,
  });

  /// All orders, most recent first.
  Future<Either<Failure, List<Order>>> getOrders();

  /// A single order by id (code).
  Future<Either<Failure, Order>> getOrderById(String id);

  /// Live tracking for an order.
  Future<Either<Failure, OrderTracking>> getTracking(String id);

  /// Cancel an order (when still cancellable).
  Future<Either<Failure, Order>> cancelOrder(String id);
}

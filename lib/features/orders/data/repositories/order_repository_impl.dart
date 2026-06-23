import 'package:dartz/dartz.dart' hide Order;

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/network/base_repository.dart';
import '../../../../core/network/network_info.dart';
import '../../../../core/storage/hive_service.dart';
import '../../../cart/domain/entities/cart_item.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/order_enums.dart';
import '../../domain/entities/order_tracking.dart';
import '../../domain/repositories/order_repository.dart';
import '../datasources/order_remote_datasource.dart';
import '../models/order_model.dart';

/// [OrderRepository] backed by the backend with a Hive `orderBox` cache mirror:
/// the server is authoritative; reads fall back to the cache when offline.
class OrderRepositoryImpl with BaseRepository implements OrderRepository {
  OrderRepositoryImpl({
    required this.remote,
    required this.hive,
    required this.networkInfo,
  });

  final OrderRemoteDataSource remote;
  final HiveService hive;

  @override
  final NetworkInfo networkInfo;

  static const _key = 'orders';

  List<Order> _readCache() {
    final raw = hive.orderBox.get(_key);
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }
    return [];
  }

  Future<void> _saveCache(List<Order> orders) =>
      hive.orderBox.put(_key, orders.map(OrderModel.toJson).toList());

  @override
  Future<Either<Failure, Order>> checkout({
    required List<CartItem> items,
    required String addressId,
    required PaymentMethod method,
    required String idempotencyKey,
    String? couponCode,
    String deliverySlot = '',
    String? creditPlan,
  }) =>
      guard(() async {
        final order = await remote.checkout(
          items: items,
          addressId: addressId,
          method: method,
          couponCode: couponCode,
          deliverySlot: deliverySlot,
          creditPlan: creditPlan,
          idempotencyKey: idempotencyKey,
        );
        final orders = _readCache()
          ..removeWhere((o) => o.id == order.id)
          ..insert(0, order);
        await _saveCache(orders);
        return order;
      });

  @override
  Future<Either<Failure, List<Order>>> getOrders() => guard(() async {
        try {
          final orders = await remote.list();
          await _saveCache(orders);
          return orders;
        } catch (_) {
          return _readCache(); // offline / transient → serve cache
        }
      }, requireConnection: false);

  @override
  Future<Either<Failure, Order>> getOrderById(String id) => guard(() async {
        try {
          final order = await remote.detail(id);
          final orders = _readCache()
            ..removeWhere((o) => o.id == id)
            ..insert(0, order);
          await _saveCache(orders);
          return order;
        } catch (_) {
          for (final o in _readCache()) {
            if (o.id == id) return o;
          }
          throw const CacheException('Order not found');
        }
      }, requireConnection: false);

  @override
  Future<Either<Failure, OrderTracking>> getTracking(String id) =>
      guard(() async {
        Order? order;
        try {
          order = await remote.detail(id);
        } catch (_) {
          for (final o in _readCache()) {
            if (o.id == id) order = o;
          }
        }
        if (order == null) throw const CacheException('Order not found');
        return await remote.tracking(order);
      }, requireConnection: false);

  @override
  Future<Either<Failure, Order>> cancelOrder(String id) => guard(() async {
        final order = await remote.cancel(id);
        final orders = _readCache()
          ..removeWhere((o) => o.id == id)
          ..insert(0, order);
        await _saveCache(orders);
        return order;
      });
}

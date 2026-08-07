import 'package:dartz/dartz.dart' hide Order;
import 'package:user_app/core/errors/failures.dart';
import 'package:user_app/core/services/analytics_service.dart';
import 'package:user_app/features/cart/domain/entities/cart.dart';
import 'package:user_app/features/cart/domain/entities/cart_item.dart';
import 'package:user_app/features/cart/domain/services/cart_validation_service.dart';
import 'package:user_app/features/orders/domain/entities/order.dart';
import 'package:user_app/features/orders/domain/entities/order_enums.dart';
import 'package:user_app/features/orders/domain/entities/order_parts.dart';
import 'package:user_app/features/orders/domain/repositories/order_repository.dart';
import 'package:user_app/features/serviceability/data/serviceability_result.dart';
import 'package:user_app/features/serviceability/presentation/providers/serviceability_providers.dart';

/// Records every checkout call so a test can assert "exactly one order request"
/// and "retry reuses the same idempotency key". Optionally fails.
class FakeOrderRepository implements OrderRepository {
  FakeOrderRepository({this.failure});

  Failure? failure;
  int checkoutCalls = 0;
  final List<String> idempotencyKeys = [];

  @override
  Future<Either<Failure, Order>> checkout({
    required List<CartItem> items,
    required String addressId,
    required PaymentMethod method,
    required String idempotencyKey,
    String? couponCode,
    String deliverySlot = '',
    String? creditPlan,
  }) async {
    checkoutCalls++;
    idempotencyKeys.add(idempotencyKey);
    await Future<void>.delayed(const Duration(milliseconds: 10)); // race window
    if (failure != null) return Left(failure!);
    return Right(_fakeOrder(method));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Order _fakeOrder(PaymentMethod method) => Order(
      id: 'ORDTEST',
      items: const [],
      address: const OrderAddress(name: 'X', phone: '9000000000', formatted: 'addr'),
      payment: OrderPayment(
          method: method, status: PaymentStatus.pending, amount: 100),
      summary: const OrderSummary(itemTotal: 100, deliveryFee: 0, grandTotal: 100),
      status: OrderStatus.confirmed,
      placedAt: DateTime(2026, 1, 1),
    );

/// Validation that returns a fixed result (default: no issues, so checkout proceeds).
class FakeCartValidationService implements CartValidationService {
  FakeCartValidationService([this.result = const CartValidationResult([])]);

  final CartValidationResult result;

  @override
  Future<CartValidationResult> validateCart(Cart cart) async => result;

  @override
  Future<bool> canCheckout(Cart cart) async => !result.hasBlocking;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Serviceability controller that returns a fixed result without touching Hive
/// (the real one reads/writes the cache box, which the fake HiveService omits).
class FakeServiceabilityController extends ServiceabilityController {
  FakeServiceabilityController(this._result);

  final ServiceabilityResult _result;

  @override
  Future<ServiceabilityResult> build() async => _result;

  @override
  Future<ServiceabilityResult> checkCoordinate({
    double? latitude,
    double? longitude,
    String? pincode,
  }) async =>
      _result;
}

/// Analytics that counts `order_placed` so a test can assert it fires exactly once.
class CountingAnalytics implements AnalyticsService {
  int orderPlaced = 0;

  @override
  void track(String name, [Map<String, Object>? params]) {
    if (name == 'order_placed') orderPlaced++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null; // other events: no-op
}

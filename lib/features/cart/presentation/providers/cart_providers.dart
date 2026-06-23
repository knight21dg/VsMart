import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/core_providers.dart';
import '../../../catalog/domain/entities/product.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';
import '../../data/datasources/cart_bill_data_source.dart';
import '../../data/repositories/cart_repository_impl.dart';
import '../../domain/entities/cart.dart';
import '../../domain/entities/cart_item.dart';
import '../../domain/repositories/cart_repository.dart';
import '../../domain/services/cart_validation_service.dart';

/// Free-delivery threshold (₹) used ONLY for the offline estimate fallback; the
/// authoritative figures come from the backend pricing engine (`/cart/quote`).
const _freeDeliveryThreshold = 499;
const _deliveryFee = 45;

final cartRepositoryProvider = Provider<CartRepository>(
  (ref) => CartRepositoryImpl(ref.watch(cartStorageProvider)),
);

/// Holds the live [Cart], loading from local storage on first build and
/// persisting through the repository on every mutation.
class CartController extends Notifier<Cart> {
  CartRepository get _repo => ref.read(cartRepositoryProvider);

  @override
  Cart build() => _repo.getCart();

  Future<void> add(CartItem item) async {
    state = await _repo.addItem(item);
    ref
        .read(analyticsServiceProvider)
        .track('cart_item_added', {'product': item.productId});
  }

  Future<void> addProduct(Product product, {int quantity = 1}) =>
      add(cartItemFrom(product, quantity: quantity));

  Future<void> setQuantity(String productId, int quantity) async {
    if (quantity <= 0) {
      ref
          .read(analyticsServiceProvider)
          .track('cart_item_removed', {'product': productId});
    }
    state = await _repo.setQuantity(productId, quantity);
  }

  Future<void> increment(String productId) =>
      setQuantity(productId, state.quantityOf(productId) + 1);

  Future<void> decrement(String productId) =>
      setQuantity(productId, state.quantityOf(productId) - 1);

  Future<void> remove(String productId) async {
    state = await _repo.removeItem(productId);
    ref
        .read(analyticsServiceProvider)
        .track('cart_item_removed', {'product': productId});
  }

  Future<void> clear() async => state = await _repo.clear();
}

final cartControllerProvider =
    NotifierProvider<CartController, Cart>(CartController.new);

/// Convenience selector for badges / summary bars.
final cartItemCountProvider =
    Provider<int>((ref) => ref.watch(cartControllerProvider).itemCount);

/// Derived bill for the cart. The single source of truth every cart/checkout
/// surface consumes. Populated from the backend pricing engine; [isEstimate]
/// is true only for the offline fallback (which omits platform/zone fees).
class CartSummary extends Equatable {
  const CartSummary({
    required this.itemsCount,
    required this.subtotal,
    required this.savings,
    required this.deliveryCharges,
    required this.gstAmount,
    required this.total,
    this.platformFee = 0,
    this.handlingFee = 0,
    this.surgeFee = 0,
    this.smallCartFee = 0,
    this.couponDiscount = 0,
    this.minOrder = 0,
    this.isEstimate = false,
  });

  final int itemsCount;
  final num subtotal;
  final num savings;
  final num deliveryCharges;
  final num gstAmount;
  final num total;
  final num platformFee;
  final num handlingFee;
  final num surgeFee;
  final num smallCartFee;
  final num couponDiscount;
  final num minOrder;

  /// True when this is the on-device estimate (backend bill not yet available).
  final bool isEstimate;

  /// All non-delivery service fees, shown as a single "Fees & charges" line.
  num get feesTotal => platformFee + handlingFee + surgeFee + smallCartFee;

  /// Amount when paying on VS Credit (same as [total] today).
  num get creditTotal => total;

  bool get qualifiesFreeDelivery => deliveryCharges == 0 && subtotal > 0;

  @override
  List<Object?> get props => [
        itemsCount,
        subtotal,
        savings,
        deliveryCharges,
        gstAmount,
        total,
        platformFee,
        handlingFee,
        surgeFee,
        smallCartFee,
        couponDiscount,
        minOrder,
        isEstimate,
      ];
}

/// Backend pricing engine for the cart bill.
final cartBillDataSourceProvider = Provider<CartBillDataSource>(
  (ref) => CartBillDataSource(ref.watch(apiClientProvider)),
);

/// Authoritative bill from `POST /cart/quote`. Null while loading the first
/// time, empty cart, or when the backend is unreachable (→ local estimate).
final cartBillProvider = FutureProvider.autoDispose<CartSummary?>((ref) async {
  final cart = ref.watch(cartControllerProvider);
  if (cart.isEmpty) return null;
  try {
    final bill = await ref.read(cartBillDataSourceProvider).quote(cart);
    return CartSummary(
      itemsCount: bill.itemsCount > 0 ? bill.itemsCount : cart.itemCount,
      subtotal: bill.subtotal,
      savings: bill.savings,
      deliveryCharges: bill.deliveryFee,
      gstAmount: bill.gst,
      platformFee: bill.platformFee,
      handlingFee: bill.handlingFee,
      surgeFee: bill.surgeFee,
      smallCartFee: bill.smallCartFee,
      couponDiscount: bill.couponDiscount,
      minOrder: bill.minOrder,
      total: bill.total,
    );
  } catch (_) {
    return null; // fall back to the on-device estimate
  }
});

/// The bill shown across cart/checkout. Prefers the authoritative backend bill;
/// falls back to an on-device estimate (clearly flagged) while it loads/offline.
final cartSummaryProvider = Provider<CartSummary>((ref) {
  final backend = ref.watch(cartBillProvider).value;
  if (backend != null) return backend;

  final cart = ref.watch(cartControllerProvider);
  final subtotal = cart.itemTotal;
  final delivery =
      (subtotal <= 0 || subtotal >= _freeDeliveryThreshold) ? 0 : _deliveryFee;
  const gstRate = 0.18;
  final gst = (subtotal * gstRate).round();
  return CartSummary(
    itemsCount: cart.itemCount,
    subtotal: subtotal,
    savings: cart.savings,
    deliveryCharges: delivery,
    gstAmount: gst,
    total: subtotal + delivery + gst,
    isEstimate: true,
  );
});

/// Stock/quantity/price validation against live catalog data.
final cartValidationServiceProvider = Provider<CartValidationService>(
  (ref) => CartValidationService(ref.watch(catalogRepositoryProvider)),
);

final cartValidationProvider = FutureProvider<CartValidationResult>((ref) async {
  final cart = ref.watch(cartControllerProvider);
  return ref.read(cartValidationServiceProvider).validateCart(cart);
});

/// Maps a catalog [Product] to a [CartItem] (quantity defaults to 1).
CartItem cartItemFrom(Product product, {int quantity = 1}) => CartItem(
      productId: product.id,
      name: product.name,
      brand: product.brand,
      unit: product.unit,
      price: product.price,
      mrp: product.mrp,
      quantity: quantity,
      imageUrl: product.imageUrl,
    );

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/error_handler.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../address/presentation/providers/address_selection_provider.dart';
import '../../../catalog/domain/entities/product.dart';
import '../../../catalog/domain/entities/product_variant.dart';
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

  /// Add a product, optionally as a specific [variant] (whose price delta is
  /// applied and whose id makes it its own cart line).
  Future<void> addProduct(
    Product product, {
    int quantity = 1,
    ProductVariant? variant,
  }) =>
      add(cartItemFrom(product, quantity: quantity, variant: variant));

  /// [lineKey] is `CartItem.lineKey` — the productId for a variant-less product,
  /// so existing product-keyed callers (grid cards) are unaffected.
  Future<void> setQuantity(String lineKey, int quantity) async {
    if (quantity <= 0) {
      ref
          .read(analyticsServiceProvider)
          .track('cart_item_removed', {'product': lineKey});
    }
    state = await _repo.setQuantity(lineKey, quantity);
  }

  Future<void> increment(String lineKey) =>
      setQuantity(lineKey, state.quantityOf(lineKey) + 1);

  Future<void> decrement(String lineKey) =>
      setQuantity(lineKey, state.quantityOf(lineKey) - 1);

  Future<void> remove(String lineKey) async {
    state = await _repo.removeItem(lineKey);
    ref
        .read(analyticsServiceProvider)
        .track('cart_item_removed', {'product': lineKey});
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
    this.deliveryFeeWaived = 0,
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

  /// Map an authoritative backend [CartBill] into a summary. [fallbackCount] is
  /// used only when the bill omits its item count.
  factory CartSummary.fromBill(CartBill bill, {required int fallbackCount}) =>
      CartSummary(
        itemsCount: bill.itemsCount > 0 ? bill.itemsCount : fallbackCount,
        subtotal: bill.subtotal,
        savings: bill.savings,
        deliveryCharges: bill.deliveryFee,
        deliveryFeeWaived: bill.deliveryFeeWaived,
        gstAmount: bill.gst,
        platformFee: bill.platformFee,
        handlingFee: bill.handlingFee,
        surgeFee: bill.surgeFee,
        smallCartFee: bill.smallCartFee,
        couponDiscount: bill.couponDiscount,
        minOrder: bill.minOrder,
        total: bill.total,
      );

  final int itemsCount;
  final num subtotal;
  final num savings;
  final num deliveryCharges;

  /// Server-supplied: what delivery would have cost when it is waived.
  /// Never hardcode this — the fee is per zone.
  final num deliveryFeeWaived;
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

  /// How much more of *goods* the shopper must add to reach the zone's minimum
  /// order value; 0 when there is no minimum or it is already met.
  ///
  /// Measured against [subtotal], not [total], because fees and GST aren't
  /// goods — counting them would clear a ₹1,000 minimum with a ₹900 basket and
  /// the server (which gates on the subtotal) would then reject the order the
  /// button had just promised. `minOrder` reached the app on every bill and was
  /// simply never read; the checkout CTA stayed live and the order failed at
  /// the very last step.
  num get minOrderShortfall {
    if (minOrder <= 0) return 0;
    final gap = minOrder - subtotal;
    return gap > 0 ? gap : 0;
  }

  /// Whether the cart clears the zone's minimum order value.
  bool get meetsMinimumOrder => minOrderShortfall <= 0;

  /// Amount when paying on VS Credit (same as [total] today).
  num get creditTotal => total;

  bool get qualifiesFreeDelivery => deliveryCharges == 0 && subtotal > 0;

  CartSummary copyWith({num? total, num? couponDiscount}) => CartSummary(
        itemsCount: itemsCount,
        subtotal: subtotal,
        savings: savings,
        deliveryCharges: deliveryCharges,
        deliveryFeeWaived: deliveryFeeWaived,
        gstAmount: gstAmount,
        total: total ?? this.total,
        platformFee: platformFee,
        handlingFee: handlingFee,
        surgeFee: surgeFee,
        smallCartFee: smallCartFee,
        couponDiscount: couponDiscount ?? this.couponDiscount,
        minOrder: minOrder,
        isEstimate: isEstimate,
      );

  @override
  List<Object?> get props => [
        itemsCount,
        subtotal,
        savings,
        deliveryCharges,
        deliveryFeeWaived,
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
/// time or for an empty cart.
///
/// Failure handling is connectivity-aware: when OFFLINE (or connectivity is
/// still resolving) a failed quote is an intended, honest degradation — we
/// return null so [cartSummaryProvider] shows the clearly-flagged on-device
/// estimate under the offline banner. When ONLINE a failed quote is NOT
/// swallowed: the local estimate can mismatch the real total, so we rethrow a
/// typed [Failure] to put this provider into an error state that the cart
/// surfaces as a "couldn't fetch the latest total — tap to retry" affordance.
final cartBillProvider = FutureProvider.autoDispose<CartSummary?>((ref) async {
  final cart = ref.watch(cartControllerProvider);
  if (cart.isEmpty) return null;
  // WATCH the address: zone fee overrides depend on it, so changing the delivery
  // address must re-quote rather than leave a total that checkout won't honour.
  final address = ref.watch(selectedAddressProvider);
  try {
    final bill = await ref
        .read(cartBillDataSourceProvider)
        .quote(cart, addressId: address?.id);
    return CartSummary.fromBill(bill, fallbackCount: cart.itemCount);
  } catch (error) {
    final online = ref.read(commerceConnectivityProvider) ==
        CommerceConnectivity.online;
    // Offline: degrade silently to the on-device estimate (the offline banner
    // already tells the user the total isn't live). Online: surface it.
    if (!online) return null;
    throw ErrorHandler.handle(error);
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

/// Per-variant, per-store stock validation via the backend `/cart/validate`.
final cartValidationServiceProvider = Provider<CartValidationService>(
  (ref) => CartValidationService(ref.watch(cartBillDataSourceProvider)),
);

final cartValidationProvider = FutureProvider<CartValidationResult>((ref) async {
  final cart = ref.watch(cartControllerProvider);
  return ref.read(cartValidationServiceProvider).validateCart(cart);
});

/// Build a cart line from a product, optionally for a specific [variant].
///
/// When a variant is given its `priceDelta` is applied — the detail screen shows
/// that adjusted price, so the cart MUST charge it. Previously this always wrote
/// the base `product.price` and never set `variantId`, so picking a +₹40 variant
/// displayed ₹40 more and silently billed the base price.
CartItem cartItemFrom(
  Product product, {
  int quantity = 1,
  ProductVariant? variant,
}) {
  final delta = variant?.priceDelta ?? 0;
  return CartItem(
    productId: product.id,
    name: variant == null ? product.name : '${product.name} · ${variant.label}',
    brand: product.brand,
    unit: product.unit,
    price: product.price + delta,
    mrp: product.mrp + delta,
    quantity: quantity,
    imageUrl: product.imageUrl,
    variantId: variant?.id,
  );
}

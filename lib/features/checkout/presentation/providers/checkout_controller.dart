import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../../../../app/constants/api_constants.dart';
import '../../../../app/constants/storage_keys.dart';
import '../../../../core/errors/failures.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../address/presentation/providers/address_selection_provider.dart';
import '../../../cart/presentation/providers/cart_providers.dart';
import '../../../credit/presentation/providers/credit_providers.dart';
import '../../../orders/domain/entities/order.dart';
import '../../../orders/domain/entities/order_enums.dart';
import '../../../orders/presentation/providers/order_providers.dart';
import '../../../payments/presentation/payment_providers.dart';
import '../../../serviceability/presentation/providers/serviceability_providers.dart';
import '../../domain/credit_checkout_validator.dart';
import '../../domain/credit_repayment_plan.dart';

/// Persisted checkout selections (delivery slot, payment, terms, coupon).
class CheckoutState extends Equatable {
  const CheckoutState({
    this.paymentMethod = PaymentMethod.cashOnDelivery,
    this.creditPlan = CreditRepaymentPlan.weekend,
    this.deliverySlot = 0,
    this.termsAccepted = true,
    this.coupon,
    this.couponDiscount = 0,
    this.placing = false,
    this.error,
    this.idempotencyKey,
  });

  final PaymentMethod paymentMethod;

  /// Chosen VS Credit repayment plan (only relevant when paying on credit).
  final CreditRepaymentPlan creditPlan;
  final int deliverySlot;
  final bool termsAccepted;
  final String? coupon;
  final num couponDiscount;
  final bool placing;
  final Failure? error;

  /// Stable key reused across retries of the same checkout so a network retry
  /// never creates a duplicate order (the backend dedupes on it).
  final String? idempotencyKey;

  CheckoutState copyWith({
    PaymentMethod? paymentMethod,
    CreditRepaymentPlan? creditPlan,
    int? deliverySlot,
    bool? termsAccepted,
    String? coupon,
    bool clearCoupon = false,
    num? couponDiscount,
    bool? placing,
    Failure? error,
    bool clearError = false,
    String? idempotencyKey,
    bool clearIdempotencyKey = false,
  }) {
    return CheckoutState(
      paymentMethod: paymentMethod ?? this.paymentMethod,
      creditPlan: creditPlan ?? this.creditPlan,
      deliverySlot: deliverySlot ?? this.deliverySlot,
      termsAccepted: termsAccepted ?? this.termsAccepted,
      coupon: clearCoupon ? null : (coupon ?? this.coupon),
      couponDiscount: clearCoupon ? 0 : (couponDiscount ?? this.couponDiscount),
      placing: placing ?? this.placing,
      error: clearError ? null : (error ?? this.error),
      idempotencyKey:
          clearIdempotencyKey ? null : (idempotencyKey ?? this.idempotencyKey),
    );
  }

  @override
  List<Object?> get props => [
        paymentMethod,
        creditPlan,
        deliverySlot,
        termsAccepted,
        coupon,
        couponDiscount,
        placing,
        error,
        idempotencyKey,
      ];
}

/// The checkout engine. Pure orchestration over cart / address / credit; the
/// draft persists to `checkoutDraftBox` so an interrupted checkout resumes.
class CheckoutController extends Notifier<CheckoutState> {
  static const _key = 'draft';

  Box<dynamic> get _box =>
      ref.read(hiveServiceProvider).box(StorageKeys.checkoutDraftBox);

  @override
  CheckoutState build() {
    final raw = _box.get(_key);
    if (raw is Map) {
      return CheckoutState(
        paymentMethod: _method(raw['paymentMethod'] as String?),
        creditPlan: CreditRepaymentPlanX.fromApi(raw['creditPlan'] as String?),
        deliverySlot: (raw['deliverySlot'] as num?)?.toInt() ?? 0,
        termsAccepted: true,
        coupon: raw['coupon'] as String?,
        couponDiscount: (raw['couponDiscount'] as num?) ?? 0,
      );
    }
    return const CheckoutState();
  }

  void _persist() => _box.put(_key, {
        'paymentMethod': state.paymentMethod.name,
        'creditPlan': state.creditPlan.apiValue,
        'deliverySlot': state.deliverySlot,
        'termsAccepted': state.termsAccepted,
        'coupon': state.coupon,
        'couponDiscount': state.couponDiscount,
      });

  void selectAddress(String id) {
    ref.read(addressSelectionProvider.notifier).select(id);
    ref.read(analyticsServiceProvider).track('address_selected', {'address': id});
  }

  void selectPaymentMethod(PaymentMethod method) {
    state = state.copyWith(paymentMethod: method);
    _persist();
    final analytics = ref.read(analyticsServiceProvider);
    analytics.track('payment_method_selected', {'method': method.name});
    if (method == PaymentMethod.credit) {
      analytics.track('credit_payment_selected');
    }
  }

  void setDeliverySlot(int slot) {
    state = state.copyWith(deliverySlot: slot);
    _persist();
  }

  /// Choose the VS Credit repayment plan (weekend / month-end).
  void selectCreditPlan(CreditRepaymentPlan plan) {
    state = state.copyWith(creditPlan: plan);
    _persist();
    ref
        .read(analyticsServiceProvider)
        .track('credit_plan_selected', {'plan': plan.apiValue});
  }

  void toggleTerms(bool value) {
    state = state.copyWith(termsAccepted: value);
    _persist();
  }

  /// Validate a coupon against the backend (`POST /coupons/validate`) so the
  /// previewed discount matches what checkout charges. Returns the outcome so
  /// the UI can surface the message.
  Future<({bool valid, String message})> applyCoupon(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty) {
      return (valid: false, message: 'Enter a coupon code');
    }
    final subtotal = ref.read(cartSummaryProvider).subtotal;
    try {
      final res = await ref.read(apiClientProvider).post<dynamic>(
        ApiConstants.couponsValidate,
        data: {'code': trimmed, 'cart_total': subtotal},
      );
      final raw = res.data;
      final data = raw is Map && raw['data'] is Map
          ? Map<String, dynamic>.from(raw['data'] as Map)
          : (raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{});
      final valid = data['valid'] == true;
      final discount = data['discount'] is num
          ? data['discount'] as num
          : num.tryParse('${data['discount']}') ?? 0;
      final message = (data['message'] ?? '').toString();
      if (valid) {
        state = state.copyWith(
            coupon: trimmed.toUpperCase(), couponDiscount: discount);
        _persist();
        return (valid: true, message: message.isEmpty ? 'Coupon applied' : message);
      }
      state = state.copyWith(clearCoupon: true);
      _persist();
      return (valid: false, message: message.isEmpty ? 'Invalid coupon' : message);
    } catch (_) {
      return (valid: false, message: 'Could not validate coupon');
    }
  }

  void removeCoupon() {
    state = state.copyWith(clearCoupon: true);
    _persist();
  }

  /// Grand total after coupon discount.
  num grandTotal() {
    final total = ref.read(cartSummaryProvider).total;
    final after = total - state.couponDiscount;
    return after < 0 ? 0 : after;
  }

  /// Place the order against the backend (server builds it from the synced cart
  /// and reserves stock). Returns the confirmed [Order] or null on failure.
  Future<Order?> placeOrder() async {
    final cart = ref.read(cartControllerProvider);
    final address = ref.read(selectedAddressProvider);
    if (cart.isEmpty || address == null || !state.termsAccepted) return null;

    final validation =
        await ref.read(cartValidationServiceProvider).validateCart(cart);
    if (validation.hasBlocking) return null;

    final total = grandTotal();
    if (state.paymentMethod == PaymentMethod.credit) {
      // Zone credit gate: block only when we've POSITIVELY resolved a serviceable
      // zone that disables BNPL — never when serviceability is simply unresolved
      // (that would wrongly block credit everywhere). The backend enforces it too.
      final svc = ref.read(currentServiceabilityProvider);
      if (svc.serviceable && !svc.creditAvailable) {
        state = state.copyWith(
          error: const ValidationFailure(
            "VS Credit isn't available in your area yet.",
          ),
        );
        return null;
      }
      final validator =
          CreditCheckoutValidator(ref.read(creditAccountProvider).valueOrNull);
      if (!validator.canPurchase(total)) return null;
    }

    // Reuse one idempotency key across retries of this checkout.
    final key =
        state.idempotencyKey ?? 'co_${DateTime.now().microsecondsSinceEpoch}';
    state = state.copyWith(placing: true, clearError: true, idempotencyKey: key);

    final result = await ref.read(orderRepositoryProvider).checkout(
          items: cart.items,
          addressId: address.id,
          method: state.paymentMethod,
          idempotencyKey: key,
          couponCode: state.coupon,
          creditPlan: state.paymentMethod == PaymentMethod.credit
              ? state.creditPlan.apiValue
              : null,
        );
    state = state.copyWith(placing: false);
    return result.fold(
      (failure) {
        state = state.copyWith(error: failure);
        return null;
      },
      (placed) {
        ref.read(lastPlacedOrderProvider.notifier).state = placed;
        ref.read(cartControllerProvider.notifier).clear();
        _box.delete(_key);
        state = state.copyWith(clearIdempotencyKey: true);
        ref.invalidate(ordersProvider);
        ref.read(analyticsServiceProvider).track('order_placed', {
          'order': placed.id,
          'amount': placed.summary.grandTotal,
          'method': placed.payment.method.name,
        });
        return placed;
      },
    );
  }

  /// Settles an online (UPI/card) order payment through Razorpay. COD and VS
  /// Credit need no gateway. In mock mode the backend auto-settles, so this is a
  /// no-op success. Returns true when paid (or no online payment was required).
  Future<bool> settleOrderPayment(Order order) async {
    final method = order.payment.method;
    if (method != PaymentMethod.upi && method != PaymentMethod.card) {
      return true;
    }
    final outcome = await ref.read(paymentServiceProvider).payForOrder(
          orderId: order.id,
          amount: order.summary.grandTotal,
          method: method == PaymentMethod.card ? 'card' : 'upi',
          phone: order.address.phone,
        );
    if (outcome.success) ref.invalidate(ordersProvider);
    return outcome.success;
  }

  PaymentMethod _method(String? name) {
    for (final m in PaymentMethod.values) {
      if (m.name == name) return m;
    }
    return PaymentMethod.cashOnDelivery;
  }
}

final checkoutControllerProvider =
    NotifierProvider<CheckoutController, CheckoutState>(CheckoutController.new);

/// The most recently placed order — read by the Order Success screen.
final lastPlacedOrderProvider = StateProvider<Order?>((ref) => null);

/// Live credit validator for the current checkout total.
final creditCheckoutValidatorProvider = Provider<CreditCheckoutValidator>(
  (ref) =>
      CreditCheckoutValidator(ref.watch(creditAccountProvider).valueOrNull),
);

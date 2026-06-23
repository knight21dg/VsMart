import 'package:equatable/equatable.dart';
import 'package:intl/intl.dart';

import '../../../../core/extensions/num_extensions.dart';

/// How a coupon's discount is computed.
enum CouponDiscountType { flat, percent }

/// A redeemable coupon from the customer's wallet (`/coupons/wallet`). Carries
/// the real terms — discount, minimum order, cap and expiry — so the coupons
/// page can render rich, Zepto-style cards.
class Coupon extends Equatable {
  const Coupon({
    required this.id,
    required this.code,
    required this.discountType,
    required this.value,
    this.minOrder,
    this.maxDiscount,
    this.validTo,
  });

  final String id;
  final String code;
  final CouponDiscountType discountType;
  final num value;
  final num? minOrder;
  final num? maxDiscount;
  final DateTime? validTo;

  bool get isPercent => discountType == CouponDiscountType.percent;

  /// Big headline, e.g. "₹100 OFF" or "15% OFF".
  String get headline =>
      isPercent ? '${value.toStringAsFixed(0)}% OFF' : '${value.asCurrency} OFF';

  /// Short qualifier under the headline (cap for percent coupons).
  String get subline {
    if (isPercent && maxDiscount != null) {
      return 'Up to ${maxDiscount!.asCurrency}';
    }
    return 'Instant discount';
  }

  /// Eligibility line, e.g. "On orders above ₹999".
  String get minOrderLabel =>
      minOrder != null && minOrder! > 0
          ? 'On orders above ${minOrder!.asCurrency}'
          : 'No minimum order';

  /// Validity line, e.g. "Valid till 30 Jun".
  String get validityLabel => validTo != null
      ? 'Valid till ${DateFormat('d MMM yyyy').format(validTo!)}'
      : 'No expiry';

  bool get isExpired =>
      validTo != null && validTo!.isBefore(DateTime.now());

  @override
  List<Object?> get props =>
      [id, code, discountType, value, minOrder, maxDiscount, validTo];
}

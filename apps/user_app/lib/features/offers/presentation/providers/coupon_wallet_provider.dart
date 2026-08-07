import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/constants/api_constants.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../domain/entities/coupon.dart';

num _num(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

/// The signed-in customer's redeemable coupons (`GET /coupons/wallet`). These
/// carry the real terms (discount, min order, cap, expiry) the Zepto-style
/// coupons page renders.
final couponWalletProvider = FutureProvider<List<Coupon>>((ref) async {
  final res = await ref
      .watch(apiClientProvider)
      .get<dynamic>(ApiConstants.couponsWallet);
  final raw = res.data;
  final data = raw is Map ? raw['data'] : raw;
  final list = data is List ? data : const [];
  return list.whereType<Map>().map((e) {
    final j = Map<String, dynamic>.from(e);
    return Coupon(
      id: (j['id'] ?? '').toString(),
      code: (j['code'] ?? '').toString(),
      discountType: j['discountType']?.toString() == 'percent'
          ? CouponDiscountType.percent
          : CouponDiscountType.flat,
      value: _num(j['value']),
      minOrder: j['minOrder'] == null ? null : _num(j['minOrder']),
      maxDiscount: j['maxDiscount'] == null ? null : _num(j['maxDiscount']),
      validTo: j['validTo'] == null
          ? null
          : DateTime.tryParse(j['validTo'].toString()),
    );
  }).toList();
});

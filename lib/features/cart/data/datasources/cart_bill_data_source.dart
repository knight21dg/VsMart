import '../../../../app/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/cart.dart';

/// Authoritative bill breakdown returned by the backend pricing engine
/// (`POST /cart/quote`). Mirrors `core/pricing.compute_bill` — GST, delivery,
/// platform/handling/surge/small-cart fees and coupon discount — so the app
/// never hand-rolls money.
class CartBill {
  const CartBill({
    required this.itemsCount,
    required this.subtotal,
    required this.savings,
    required this.deliveryFee,
    required this.gst,
    required this.platformFee,
    required this.handlingFee,
    required this.surgeFee,
    required this.smallCartFee,
    required this.couponDiscount,
    required this.total,
    required this.minOrder,
  });

  final int itemsCount;
  final num subtotal;
  final num savings;
  final num deliveryFee;
  final num gst;
  final num platformFee;
  final num handlingFee;
  final num surgeFee;
  final num smallCartFee;
  final num couponDiscount;
  final num total;
  final num minOrder;
}

/// Fetches the authoritative cart bill from the backend without mutating the
/// server cart.
class CartBillDataSource {
  CartBillDataSource(this._client);

  final ApiClient _client;

  num _num(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
  int _int(dynamic v) => _num(v).toInt();

  Future<CartBill> quote(Cart cart, {num couponDiscount = 0}) async {
    final res = await _client.post<dynamic>(
      ApiConstants.cartQuote,
      data: {
        'items': [
          for (final i in cart.items)
            {
              'product_id': i.productId,
              'quantity': i.quantity,
              if (i.variantId != null) 'variant_id': i.variantId,
            },
        ],
        if (couponDiscount > 0) 'coupon_discount': couponDiscount,
      },
    );
    final data = res.data is Map && (res.data as Map)['data'] is Map
        ? (res.data as Map)['data']
        : res.data;
    final bill = (data is Map ? data['bill'] : null);
    final b = bill is Map ? Map<String, dynamic>.from(bill) : <String, dynamic>{};
    return CartBill(
      itemsCount: _int(b['itemsCount']),
      subtotal: _num(b['subtotal']),
      savings: _num(b['savings']),
      deliveryFee: _num(b['deliveryFee']),
      gst: _num(b['gst']),
      platformFee: _num(b['platformFee']),
      handlingFee: _num(b['handlingFee']),
      surgeFee: _num(b['surgeFee']),
      smallCartFee: _num(b['smallCartFee']),
      couponDiscount: _num(b['couponDiscount']),
      total: _num(b['total']),
      minOrder: _num(b['minOrder']),
    );
  }
}

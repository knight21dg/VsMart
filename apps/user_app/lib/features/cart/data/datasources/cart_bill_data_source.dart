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

/// One cart line's live stock status at the serving store, from `/cart/validate`.
class StockLine {
  const StockLine({
    required this.productId,
    required this.variantId,
    required this.name,
    required this.requested,
    required this.available,
    required this.inStock,
  });

  final String productId;
  final String? variantId;
  final String name;
  final int requested;

  /// Units available for THIS pack at the serving store (null = store unknown).
  final int? available;
  final bool inStock;
}

/// Result of the pre-checkout stock check.
class CartStockCheck {
  const CartStockCheck({required this.ok, required this.lines});
  final bool ok;
  final List<StockLine> lines;

  List<StockLine> get shortfalls => lines.where((l) => !l.inStock).toList();
}

/// The stock-check capability the cart validator depends on (so it can be faked in
/// tests). [CartBillDataSource] is the real implementation.
abstract class CartStockChecker {
  Future<CartStockCheck> validate(Cart cart);
}

/// Fetches the authoritative cart bill from the backend without mutating the
/// server cart.
class CartBillDataSource implements CartStockChecker {
  CartBillDataSource(this._client);

  final ApiClient _client;

  num _num(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
  int _int(dynamic v) => _num(v).toInt();

  /// Re-check every line's stock at the serving store before checkout. The final
  /// guard is still the reserve at Pay, but this surfaces out-of-stock lines up
  /// front instead of failing late.
  @override
  Future<CartStockCheck> validate(Cart cart) async {
    final res = await _client.post<dynamic>(
      ApiConstants.cartValidate,
      data: {
        'items': [
          for (final i in cart.items)
            {
              'product_id': i.productId,
              'quantity': i.quantity,
              if (i.variantId != null) 'variant_id': i.variantId,
            },
        ],
      },
    );
    final data = res.data is Map && (res.data as Map)['data'] is Map
        ? (res.data as Map)['data']
        : res.data;
    final map = data is Map ? data : <String, dynamic>{};
    final rawLines = (map['items'] as List?) ?? const [];
    return CartStockCheck(
      ok: map['ok'] == true,
      lines: [
        for (final l in rawLines)
          if (l is Map)
            StockLine(
              productId: (l['productId'] ?? '').toString(),
              variantId: l['variantId']?.toString(),
              name: (l['name'] ?? '').toString(),
              requested: _int(l['requested']),
              available: l['available'] == null ? null : _int(l['available']),
              inStock: l['inStock'] == true,
            ),
      ],
    );
  }

  /// Authoritative bill preview for [cart].
  ///
  /// [addressId] is the delivery address the customer has selected. It matters
  /// for money: a zone overrides the delivery fee, the free-delivery threshold,
  /// the platform fee and the min-order, and checkout resolves the zone from the
  /// real address. Quoting without it showed the platform defaults and then
  /// charged the zone rate — the total changed between the cart and the receipt.
  Future<CartBill> quote(
    Cart cart, {
    num couponDiscount = 0,
    String? addressId,
  }) async {
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
        if (addressId != null && addressId.isNotEmpty) 'address_id': addressId,
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

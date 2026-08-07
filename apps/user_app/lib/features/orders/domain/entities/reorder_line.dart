import 'package:equatable/equatable.dart';

import '../../../cart/domain/entities/cart_item.dart';

/// Why a past order line can't go back in the cart. Mirrors the backend's
/// `REORDER_*` reasons — "we stopped selling this" and "it's sold out right now"
/// deserve different words to a customer.
enum ReorderUnavailableReason {
  discontinued,
  outOfStock,
  unknown;

  static ReorderUnavailableReason parse(String? raw) => switch (raw) {
        'discontinued' => ReorderUnavailableReason.discontinued,
        'out_of_stock' => ReorderUnavailableReason.outOfStock,
        _ => ReorderUnavailableReason.unknown,
      };
}

/// One line of a reorder, as the server plans it.
///
/// Carries everything a cart line needs, so reordering costs ONE request instead
/// of re-fetching each product individually. Prices are live rather than the
/// historical ones on the order — showing what you paid last time would promise a
/// total the cart won't honour.
class ReorderLine extends Equatable {
  const ReorderLine({
    required this.name,
    required this.quantity,
    required this.available,
    this.productId,
    this.variantId,
    this.brand = '',
    this.unit = '',
    this.price,
    this.mrp,
    this.imageUrl,
    this.reason = ReorderUnavailableReason.unknown,
  });

  factory ReorderLine.fromJson(Map<String, dynamic> json) {
    final available = json['available'] == true;
    return ReorderLine(
      productId: json['productId']?.toString(),
      variantId: json['variantId']?.toString(),
      name: (json['name'] ?? '').toString(),
      brand: (json['brand'] ?? '').toString(),
      unit: (json['unit'] ?? '').toString(),
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      price: (json['price'] as num?),
      mrp: (json['mrp'] as num?),
      imageUrl: (json['imageUrl'] ?? '').toString(),
      available: available,
      reason: available
          ? ReorderUnavailableReason.unknown
          : ReorderUnavailableReason.parse(json['reason']?.toString()),
    );
  }

  /// Null when the product was delisted — there is nothing left to point at.
  final String? productId;
  final String? variantId;
  final String name;
  final String brand;
  final String unit;
  final int quantity;
  final num? price;
  final num? mrp;
  final String? imageUrl;
  final bool available;
  final ReorderUnavailableReason reason;

  num get lineTotal => (price ?? 0) * quantity;

  /// The cart line this becomes. Only valid for an available line — an
  /// unavailable one has no live price and may have no product at all.
  CartItem toCartItem() => CartItem(
        productId: productId!,
        variantId: variantId,
        name: name,
        brand: brand,
        unit: unit,
        price: price ?? 0,
        // Never let mrp fall below price, or the UI renders a negative saving.
        mrp: (mrp != null && mrp! > (price ?? 0)) ? mrp! : (price ?? 0),
        quantity: quantity,
        imageUrl: imageUrl,
      );

  @override
  List<Object?> get props => [
        productId, variantId, name, brand, unit, quantity,
        price, mrp, imageUrl, available, reason,
      ];
}

/// The whole plan: what would go in, and what can't.
class ReorderPlan extends Equatable {
  const ReorderPlan({required this.lines});

  factory ReorderPlan.fromJson(Map<String, dynamic> json) => ReorderPlan(
        lines: ((json['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => ReorderLine.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
      );

  final List<ReorderLine> lines;

  List<ReorderLine> get available =>
      lines.where((l) => l.available).toList(growable: false);
  List<ReorderLine> get unavailable =>
      lines.where((l) => !l.available).toList(growable: false);

  bool get isEmpty => lines.isEmpty;
  bool get hasAnythingToAdd => available.isNotEmpty;
  num get total => available.fold<num>(0, (sum, l) => sum + l.lineTotal);

  @override
  List<Object?> get props => [lines];
}

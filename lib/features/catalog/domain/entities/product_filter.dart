import 'package:equatable/equatable.dart';

import 'product.dart';

/// Sort orders for product listings.
enum ProductSort { popularity, newest, priceLowToHigh, priceHighToLow, discount }

extension ProductSortX on ProductSort {
  String get label => switch (this) {
        ProductSort.popularity => 'Popularity',
        ProductSort.newest => 'Newest',
        ProductSort.priceLowToHigh => 'Price: Low to High',
        ProductSort.priceHighToLow => 'Price: High to Low',
        ProductSort.discount => 'Discount',
      };
}

/// Immutable product filter. The same model powers Listing, Search, Offers and
/// Wishlist so they share one filtering engine.
class ProductFilter extends Equatable {
  const ProductFilter({
    this.minPrice,
    this.maxPrice,
    this.inStockOnly = false,
    this.brands = const [],
    this.categories = const [],
    this.subCategories = const [],
    this.minimumDiscount,
  });

  final double? minPrice;
  final double? maxPrice;
  final bool inStockOnly;
  final List<String> brands;
  final List<String> categories;
  final List<String> subCategories;
  final double? minimumDiscount;

  static const empty = ProductFilter();

  bool get isActive =>
      minPrice != null ||
      maxPrice != null ||
      inStockOnly ||
      brands.isNotEmpty ||
      categories.isNotEmpty ||
      subCategories.isNotEmpty ||
      minimumDiscount != null;

  /// Whether [p] passes this filter.
  bool matches(Product p) {
    if (inStockOnly && !p.inStock) return false;
    if (minPrice != null && p.price < minPrice!) return false;
    if (maxPrice != null && p.price > maxPrice!) return false;
    if (brands.isNotEmpty && !brands.contains(p.brand)) return false;
    if (subCategories.isNotEmpty && !subCategories.contains(p.categoryId)) {
      return false;
    }
    if (categories.isNotEmpty && !categories.contains(p.categoryId)) {
      return false;
    }
    if (minimumDiscount != null && p.discountPercent < minimumDiscount!) {
      return false;
    }
    return true;
  }

  ProductFilter copyWith({
    double? minPrice,
    bool clearMinPrice = false,
    double? maxPrice,
    bool clearMaxPrice = false,
    bool? inStockOnly,
    List<String>? brands,
    List<String>? categories,
    List<String>? subCategories,
    double? minimumDiscount,
    bool clearDiscount = false,
  }) {
    return ProductFilter(
      minPrice: clearMinPrice ? null : (minPrice ?? this.minPrice),
      maxPrice: clearMaxPrice ? null : (maxPrice ?? this.maxPrice),
      inStockOnly: inStockOnly ?? this.inStockOnly,
      brands: brands ?? this.brands,
      categories: categories ?? this.categories,
      subCategories: subCategories ?? this.subCategories,
      minimumDiscount:
          clearDiscount ? null : (minimumDiscount ?? this.minimumDiscount),
    );
  }

  /// Active filters as removable chips (label + the filter with it removed).
  List<({String label, ProductFilter cleared})> activeChips() {
    final chips = <({String label, ProductFilter cleared})>[];
    if (inStockOnly) {
      chips.add((label: 'In stock', cleared: copyWith(inStockOnly: false)));
    }
    if (minPrice != null || maxPrice != null) {
      final lo = minPrice?.round();
      final hi = maxPrice?.round();
      chips.add((
        label: '₹${lo ?? 0} – ₹${hi ?? '∞'}',
        cleared: copyWith(clearMinPrice: true, clearMaxPrice: true),
      ));
    }
    for (final b in brands) {
      chips.add((
        label: b,
        cleared: copyWith(brands: brands.where((x) => x != b).toList()),
      ));
    }
    if (minimumDiscount != null) {
      chips.add((
        label: '${minimumDiscount!.round()}%+ off',
        cleared: copyWith(clearDiscount: true),
      ));
    }
    return chips;
  }

  @override
  List<Object?> get props => [
        minPrice,
        maxPrice,
        inStockOnly,
        brands,
        categories,
        subCategories,
        minimumDiscount,
      ];
}

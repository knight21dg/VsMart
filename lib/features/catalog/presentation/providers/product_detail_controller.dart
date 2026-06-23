import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_price.dart';
import '../../domain/entities/product_variant.dart';
import 'catalog_providers.dart';
import 'recently_viewed_provider.dart';

/// State of the product detail interaction: the loaded product plus the
/// selected variant and quantity, with derived pricing/stock.
class DetailState extends Equatable {
  const DetailState({
    this.product,
    this.loading = true,
    this.error,
    this.variantIndex = 0,
    this.quantity = 1,
  });

  final Product? product;
  final bool loading;
  final Failure? error;
  final int variantIndex;
  final int quantity;

  ProductVariant? get selectedVariant {
    final p = product;
    if (p == null || p.variants.isEmpty) return null;
    return p.variants[variantIndex.clamp(0, p.variants.length - 1)];
  }

  /// Pricing adjusted by the selected variant's price delta.
  ProductPrice get pricing {
    final p = product;
    if (p == null) return const ProductPrice(sellingPrice: 0, mrp: 0);
    final delta = selectedVariant?.priceDelta ?? 0;
    return ProductPrice(
      sellingPrice: p.price + delta,
      mrp: p.mrp + delta,
      creditPrice: p.creditPrice == null ? null : p.creditPrice! + delta,
    );
  }

  StockStatus get stockStatus => product?.stockStatus ?? StockStatus.outOfStock;

  bool get canPurchase =>
      stockStatus != StockStatus.outOfStock &&
      (selectedVariant?.inStock ?? true);

  int get maxQuantity => product?.stockCount ?? 99;

  num get lineTotal => pricing.sellingPrice * quantity;

  DetailState copyWith({
    Product? product,
    bool? loading,
    Failure? error,
    bool clearError = false,
    int? variantIndex,
    int? quantity,
  }) {
    return DetailState(
      product: product ?? this.product,
      loading: loading ?? this.loading,
      error: clearError ? null : (error ?? this.error),
      variantIndex: variantIndex ?? this.variantIndex,
      quantity: quantity ?? this.quantity,
    );
  }

  @override
  List<Object?> get props =>
      [product, loading, error, variantIndex, quantity];
}

/// Central product-interaction controller: loads the product, tracks the view,
/// and owns variant/quantity selection. The detail screen is a pure view.
class ProductDetailController extends FamilyNotifier<DetailState, String> {
  @override
  DetailState build(String productId) {
    Future.microtask(_load);
    return const DetailState(loading: true);
  }

  Future<void> _load() async {
    state = state.copyWith(loading: true, clearError: true);
    // Record the view + analytics before the product resolves.
    unawaited(ref.read(recentlyViewedProvider.notifier).add(arg));
    ref.read(analyticsServiceProvider).track('product_opened', {'product': arg});

    final result = await ref.read(catalogRepositoryProvider).getProductById(arg);
    result.fold(
      (failure) => state = state.copyWith(loading: false, error: failure),
      (product) =>
          state = DetailState(product: product, loading: false, quantity: 1),
    );
  }

  Future<void> retry() => _load();

  void selectVariant(int index) {
    state = state.copyWith(variantIndex: index, quantity: 1);
    final label = state.selectedVariant?.label;
    ref.read(analyticsServiceProvider).track('variant_selected', {
      if (label != null) 'variant': label,
      'product': arg,
    });
  }

  void setQuantity(int quantity) {
    final clamped = quantity.clamp(1, state.maxQuantity);
    if (clamped == state.quantity) return;
    state = state.copyWith(quantity: clamped);
    ref
        .read(analyticsServiceProvider)
        .track('quantity_changed', {'quantity': clamped, 'product': arg});
  }

  void increment() => setQuantity(state.quantity + 1);
  void decrement() => setQuantity(state.quantity - 1);
}

final productDetailControllerProvider =
    NotifierProvider.family<ProductDetailController, DetailState, String>(
        ProductDetailController.new);

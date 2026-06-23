import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/core_providers.dart';
import '../../data/repositories/recently_viewed_repository_impl.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/recently_viewed_repository.dart';
import 'catalog_providers.dart';

final recentlyViewedRepositoryProvider = Provider<RecentlyViewedRepository>(
  (ref) => RecentlyViewedRepositoryImpl(ref.watch(hiveServiceProvider)),
);

/// Exposes recently-viewed product ids (most-recent first), backed by
/// [RecentlyViewedRepository]. Powers "Continue Shopping" and recommendations.
class RecentlyViewedController extends Notifier<List<String>> {
  RecentlyViewedRepository get _repo =>
      ref.read(recentlyViewedRepositoryProvider);

  @override
  List<String> build() => _repo.getRecent().map((e) => e.productId).toList();

  Future<void> add(String productId) async {
    final entries = await _repo.addViewed(productId);
    state = entries.map((e) => e.productId).toList();
    ref
        .read(analyticsServiceProvider)
        .track('recently_viewed_added', {'product': productId});
  }

  Future<void> remove(String productId) async {
    state = (await _repo.removeViewed(productId)).map((e) => e.productId).toList();
  }

  Future<void> clear() async {
    await _repo.clear();
    state = const [];
  }
}

final recentlyViewedProvider =
    NotifierProvider<RecentlyViewedController, List<String>>(
        RecentlyViewedController.new);

/// Resolves recently-viewed ids to products for the "Continue Shopping" rail.
final recentlyViewedProductsProvider = FutureProvider<List<Product>>((ref) async {
  final ids = ref.watch(recentlyViewedProvider);
  if (ids.isEmpty) return const [];
  final repo = ref.watch(catalogRepositoryProvider);
  final products = <Product>[];
  for (final id in ids) {
    final result = await repo.getProductById(id);
    result.fold((_) {}, products.add);
  }
  return products;
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/constants/api_constants.dart';
import '../../../../app/constants/storage_keys.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../catalog/domain/entities/product.dart';
import '../../../catalog/presentation/providers/catalog_providers.dart';

/// Saved product ids (most-recent first), backed by `/api/v1/wishlist` with a
/// Hive cache mirror: toggles update the cache instantly (snappy hearts) and sync
/// to the backend; the list hydrates from the server on build.
class WishlistController extends Notifier<List<String>> {
  ApiClient get _api => ref.read(apiClientProvider);

  List<String> _cached() => (ref
          .read(hiveServiceProvider)
          .box(StorageKeys.wishlistBox)
          .get(StorageKeys.wishlistItems, defaultValue: const <dynamic>[]) as List)
      .cast<String>();

  @override
  List<String> build() {
    _hydrate();
    return _cached();
  }

  Future<void> _hydrate() async {
    try {
      final res = await _api.get<dynamic>(ApiConstants.wishlist);
      final data = (res.data is Map ? res.data['data'] : res.data) as List? ?? const [];
      state = data.whereType<Map>().map((e) => e['id'].toString()).toList();
      await _persist();
    } catch (_) {/* offline → keep cache */}
  }

  bool contains(String productId) => state.contains(productId);

  Future<void> toggle(String productId) async {
    final adding = !state.contains(productId);
    state = adding
        ? [productId, ...state]
        : state.where((id) => id != productId).toList();
    await _persist();
    try {
      adding
          ? await _api.post<dynamic>(ApiConstants.wishlistItem(productId))
          : await _api.delete<dynamic>(ApiConstants.wishlistItem(productId));
    } catch (_) {/* will reconcile on next hydrate */}
    ref.read(analyticsServiceProvider).track('wishlist_toggled', {
      'product': productId,
      'saved': adding,
    });
  }

  Future<void> remove(String productId) async {
    state = state.where((id) => id != productId).toList();
    await _persist();
    try {
      await _api.delete<dynamic>(ApiConstants.wishlistItem(productId));
    } catch (_) {}
  }

  Future<void> clear() async {
    final ids = [...state];
    state = const [];
    await _persist();
    for (final id in ids) {
      try {
        await _api.delete<dynamic>(ApiConstants.wishlistItem(id));
      } catch (_) {}
    }
  }

  Future<void> _persist() => ref
      .read(hiveServiceProvider)
      .box(StorageKeys.wishlistBox)
      .put(StorageKeys.wishlistItems, state);
}

final wishlistProvider =
    NotifierProvider<WishlistController, List<String>>(WishlistController.new);

/// Whether a given product is wishlisted (for heart toggles).
final isWishlistedProvider = Provider.family<bool, String>(
  (ref, productId) => ref.watch(wishlistProvider).contains(productId),
);

/// Resolves the wishlist ids to full [Product]s for the wishlist screen.
///
/// Fetches all ids concurrently ([Future.wait]) rather than serially, so a long
/// wishlist resolves in one round-trip's time instead of N. Ordering is
/// preserved (results map 1:1 to [ids]); ids that fail to resolve are dropped
/// rather than failing the whole list.
final wishlistProductsProvider = FutureProvider<List<Product>>((ref) async {
  final ids = ref.watch(wishlistProvider);
  if (ids.isEmpty) return const [];
  final repo = ref.watch(catalogRepositoryProvider);
  final results = await Future.wait(ids.map(repo.getProductById));
  return [
    for (final result in results)
      ...result.fold((_) => const <Product>[], (p) => [p]),
  ];
});

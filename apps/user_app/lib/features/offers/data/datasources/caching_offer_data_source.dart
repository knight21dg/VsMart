import '../../../../app/constants/storage_keys.dart';
import '../../../../core/storage/commerce_cache_manager.dart';
import '../../domain/entities/offer.dart';
import '../models/offer_model.dart';
import 'offer_data_source.dart';

/// Stale-while-revalidate wrapper around an [OfferDataSource].
class CachingOfferDataSource implements OfferDataSource {
  CachingOfferDataSource({
    required this.remote,
    required this.cache,
    this.scope = 'global',
  });

  final OfferDataSource remote;
  final CommerceCacheManager cache;

  /// Serving store this cache belongs to. Offers are zone/store-targeted
  /// server-side, but the keys were global — so after changing zone the app kept
  /// showing the previous zone's banners and deals for the whole TTL, and
  /// indefinitely while offline.
  final String scope;

  static const _ttl = Duration(minutes: 5);

  Future<List<Offer>> _swr(String rawKey, Future<List<Offer>> Function() fetch) async {
    final key = '$scope::$rawKey';
    if (cache.isFresh(StorageKeys.offerBox, key, _ttl)) {
      final cached = cache.readList(StorageKeys.offerBox, key);
      if (cached != null) return cached.map(OfferModel.fromJson).toList();
    }
    try {
      final fresh = await fetch();
      await cache.writeList(
          StorageKeys.offerBox, key, fresh.map(OfferModel.toJson).toList());
      return fresh;
    } catch (_) {
      final cached = cache.readList(StorageKeys.offerBox, key);
      if (cached != null) return cached.map(OfferModel.fromJson).toList();
      rethrow;
    }
  }

  @override
  Future<List<Offer>> getBanners() => _swr('banners', remote.getBanners);

  @override
  Future<List<Offer>> getDeals() => _swr('deals', remote.getDeals);

  @override
  Future<List<Offer>> getCoupons() => _swr('coupons', remote.getCoupons);
}

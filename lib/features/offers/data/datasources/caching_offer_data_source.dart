import '../../../../app/constants/storage_keys.dart';
import '../../../../core/storage/commerce_cache_manager.dart';
import '../../domain/entities/offer.dart';
import '../models/offer_model.dart';
import 'offer_data_source.dart';

/// Stale-while-revalidate wrapper around an [OfferDataSource].
class CachingOfferDataSource implements OfferDataSource {
  CachingOfferDataSource({required this.remote, required this.cache});

  final OfferDataSource remote;
  final CommerceCacheManager cache;

  static const _ttl = Duration(minutes: 5);

  Future<List<Offer>> _swr(String key, Future<List<Offer>> Function() fetch) async {
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

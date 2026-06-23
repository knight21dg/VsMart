import '../../domain/entities/offer.dart';

/// Data-source contract for offers. Implemented by [OfferBackendDataSource] (the
/// public `/offers` API) and wrapped by [CachingOfferDataSource].
abstract interface class OfferDataSource {
  Future<List<Offer>> getBanners();
  Future<List<Offer>> getDeals();
  Future<List<Offer>> getCoupons();
}

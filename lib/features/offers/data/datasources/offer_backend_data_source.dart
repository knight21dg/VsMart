import '../../../../core/network/api_client.dart';
import '../../domain/entities/offer.dart';
import 'offer_data_source.dart';

/// [OfferDataSource] backed by the public backend offers API (`/offers?type=`).
class OfferBackendDataSource implements OfferDataSource {
  OfferBackendDataSource(this._client);

  final ApiClient _client;

  List<Map<String, dynamic>> _list(dynamic raw) {
    final data = raw is Map ? raw['data'] : raw;
    final list = data is List ? data : const [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Offer>> _fetch(String type) async {
    final res = await _client.get<dynamic>(
      '/offers',
      query: {'type': type},
      options: ApiClient.noAuth(),
    );
    return _list(res.data).map(_toOffer).toList();
  }

  @override
  Future<List<Offer>> getBanners() => _fetch('banner');

  @override
  Future<List<Offer>> getDeals() => _fetch('deal');

  @override
  Future<List<Offer>> getCoupons() => _fetch('coupon');

  /// Fetch banners targeted at a screen [placement] (e.g. `product_list`,
  /// `product_detail`), optionally scoped to a [categoryId] / [subcategoryId].
  /// The server returns category-targeted banners first, then marketing
  /// fallbacks (`is_fallback`). Returns an empty list on any error so the UI
  /// can render nothing instead of breaking.
  Future<List<Offer>> getPlacementBanners({
    required String placement,
    String? categoryId,
    String? subcategoryId,
  }) async {
    try {
      final res = await _client.get<dynamic>(
        '/offers',
        query: {
          'type': 'banner',
          'placement': placement,
          if (categoryId != null && categoryId.isNotEmpty)
            'category': categoryId,
          if (subcategoryId != null && subcategoryId.isNotEmpty)
            'subcategory': subcategoryId,
        },
        options: ApiClient.noAuth(),
      );
      return _list(res.data).map(_toOffer).toList();
    } catch (_) {
      return const [];
    }
  }

  Offer _toOffer(Map<String, dynamic> j) => Offer(
        id: (j['id'] ?? '').toString(),
        type: switch (j['type']?.toString()) {
          'deal' => OfferType.deal,
          'coupon' => OfferType.coupon,
          _ => OfferType.banner,
        },
        placement: switch (j['placement']?.toString()) {
          'middle' => BannerPlacement.middle,
          'spotlight' => BannerPlacement.spotlight,
          _ => BannerPlacement.top,
        },
        title: (j['title'] ?? '').toString(),
        subtitle: (j['subtitle'] ?? '').toString(),
        code: j['code'] as String?,
        imageUrl: (j['imageUrl'] ?? j['image_url'])?.toString(),
        badge: j['badge'] as String?,
        discountPercent: (j['discountPercent'] as num?)?.toInt(),
        dealPrice: j['dealPrice'] as num?,
        originalPrice: j['originalPrice'] as num?,
        productId: (j['productId'] ?? j['product_id'])?.toString(),
        targetPlacement: j['placement']?.toString(),
        categoryId: (j['category_id'] ?? j['categoryId'])?.toString(),
        subcategoryId:
            (j['subcategory_id'] ?? j['subcategoryId'])?.toString(),
        isFallback: (j['is_fallback'] ?? j['isFallback']) == true,
      );
}

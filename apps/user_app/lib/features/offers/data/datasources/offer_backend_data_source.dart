import '../../../../app/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/offer.dart';
import 'offer_data_source.dart';

/// [OfferDataSource] backed by the public backend offers API (`/offers?type=`).
///
/// Sends the customer's LOCATION (lat/lng/pincode) as context so the backend
/// resolves the serving zone/store itself and returns only the banners valid for
/// that area (zone/store targeting + in-stock filtering happen server-side).
class OfferBackendDataSource implements OfferDataSource {
  OfferBackendDataSource(this._client, {this.lat, this.lng, this.pincode});

  final ApiClient _client;
  final double? lat;
  final double? lng;
  final String? pincode;

  Map<String, dynamic> get _location => {
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (pincode != null && pincode!.isNotEmpty) 'pincode': pincode,
      };

  List<Map<String, dynamic>> _list(dynamic raw) {
    final data = raw is Map ? raw['data'] : raw;
    final list = data is List ? data : const [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<List<Offer>> _fetch(String type) async {
    final res = await _client.get<dynamic>(
      '/offers',
      query: {'type': type, ..._location},
      options: ApiClient.noAuth(),
    );
    return _list(res.data).map(_toOffer).toList();
  }

  /// Fire-and-forget banner analytics. Posts a batch of
  /// `{offer_id, kind, click_id?}` events to `/offers/events`; swallows errors
  /// so telemetry never disrupts the UI.
  Future<void> sendEvents(List<Map<String, dynamic>> events) async {
    if (events.isEmpty) return;
    try {
      await _client.post<dynamic>(
        '/offers/events',
        data: {'events': events},
        options: ApiClient.noAuth(),
      );
    } catch (_) {
      // telemetry is best-effort
    }
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
          ..._location,
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
        placement: BannerPlacement.parse(j['placement']?.toString()),
        title: (j['title'] ?? '').toString(),
        subtitle: (j['subtitle'] ?? '').toString(),
        titleTe: (j['titleTe'] ?? j['title_te'] ?? '').toString(),
        titleHi: (j['titleHi'] ?? j['title_hi'] ?? '').toString(),
        subtitleTe: (j['subtitleTe'] ?? j['subtitle_te'] ?? '').toString(),
        subtitleHi: (j['subtitleHi'] ?? j['subtitle_hi'] ?? '').toString(),
        code: j['code'] as String?,
        imageUrl: (j['imageUrl'] ?? j['image_url'])?.toString(),
        image: _image(j['image']),
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
        isPinned: (j['isPinned'] ?? j['is_pinned']) == true,
        action: OfferAction.parse(j['action']?.toString()),
        payload: j['payload'] is Map
            ? Map<String, dynamic>.from(j['payload'] as Map)
            : const {},
        ctaText: (j['ctaText'] ?? j['cta_text'] ?? '').toString(),
        ctaTextTe: (j['ctaTextTe'] ?? j['cta_text_te'] ?? '').toString(),
        ctaTextHi: (j['ctaTextHi'] ?? j['cta_text_hi'] ?? '').toString(),
        textTheme:
            BannerTextTheme.parse((j['textTheme'] ?? j['text_theme'])?.toString()),
        textPosition: BannerTextPosition.parse(
            (j['textPosition'] ?? j['text_position'])?.toString()),
        accentColor: (j['accentColor'] ?? j['accent_color'])?.toString(),
      );

  /// Parse the server `image` object into a [BannerImage] with absolute URLs.
  /// The size variants come back as host-root paths (`/media/...`) which we
  /// resolve against the API origin. Legacy banners (no `image`) return null.
  static BannerImage? _image(dynamic raw) {
    if (raw is! Map) return null;
    final cfg = AppConfig.instance;
    String? url(dynamic v) =>
        (v is String && v.isNotEmpty) ? cfg.assetUrl(v) : null;
    final focus = raw['focus'];
    final fx = (focus is Map ? (focus['x'] as num?) : null)?.toDouble() ?? 0.5;
    final fy = (focus is Map ? (focus['y'] as num?) : null)?.toDouble() ?? 0.5;
    final img = BannerImage(
      large: url(raw['large']),
      medium: url(raw['medium']),
      small: url(raw['small']),
      thumb: url(raw['thumb']),
      focusX: fx,
      focusY: fy,
    );
    // A legacy fallback ({legacy_url}) has no size variants — treat as no image.
    return (img.large ?? img.medium ?? img.small ?? img.thumb) == null
        ? null
        : img;
  }
}

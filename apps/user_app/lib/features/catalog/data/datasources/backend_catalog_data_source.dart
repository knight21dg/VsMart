import '../../../../app/config/app_config.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/pagination.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_variant.dart';
import '../../domain/entities/search_suggestions.dart';
import 'catalog_data_source.dart';

/// [CatalogDataSource] backed by the VS Mart backend (`/api/v1`). Unwraps the
/// `{ success, message, data, meta }` envelope and maps the backend's camelCase
/// product/category JSON onto the catalog domain entities.
///
/// Wrapped by [CachingCatalogDataSource], so responses are cached for offline use.
class BackendCatalogDataSource implements CatalogDataSource {
  BackendCatalogDataSource(
    this._client, {
    this.lat,
    this.lng,
    this.pincode,
    this.storeId,
  });

  final ApiClient _client;

  /// The customer's delivery LOCATION. The backend resolves the serving store
  /// from this (zone → store) and returns only that store's catalog — the store
  /// is never chosen by the client, so a customer can't widen what they see.
  final double? lat;
  final double? lng;
  final String? pincode;

  /// Transitional fallback only: the already-resolved store id. The backend
  /// prefers the location above and uses this only if location can't resolve a
  /// zone, so it can never override the customer's real serving store.
  final String? storeId;

  /// Location-first scope sent on every catalog query (no-op until the backend
  /// `zone_store_visibility` flag is on).
  Map<String, dynamic> get _scopeQuery => {
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (pincode != null && pincode!.isNotEmpty) 'pincode': pincode,
        if (storeId != null) 'store': storeId,
      };

  // ---- envelope helpers ----
  List<Map<String, dynamic>> _list(dynamic raw) {
    final data = raw is Map ? raw['data'] : raw;
    final list = data is List ? data : const [];
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  /// Reads `meta.totalPages` from the paginated envelope (camelCased by the
  /// backend renderer); defaults to a single page when absent.
  int _totalPages(dynamic raw) {
    final meta = raw is Map ? raw['meta'] : null;
    if (meta is Map) {
      final tp = meta['totalPages'] ?? meta['total_pages'];
      if (tp is num) return tp.toInt();
    }
    return 1;
  }

  /// Walks every page of a `/products` (or `/products/search`) query and returns
  /// the full result set — no silent truncation at a single page. Bounded by a
  /// generous safety cap so a pathological category can't fetch unboundedly.
  Future<List<Product>> _fetchAllPages(
    String path,
    Map<String, dynamic> baseQuery,
  ) async {
    const pageSize = 100;
    const maxPages = 20; // hard ceiling = 2000 items
    final all = <Product>[];
    var page = 1;
    while (page <= maxPages) {
      final res = await _client.get<dynamic>(
        path,
        query: {...baseQuery, 'page': page, 'page_size': pageSize},
        options: ApiClient.noAuth(),
      );
      final items = _list(res.data).map(_toProduct).toList();
      all.addAll(items);
      if (items.isEmpty || page >= _totalPages(res.data)) break;
      page++;
    }
    return all;
  }

  /// Fetches a SINGLE page of a `/products` (or `/products/search`) query and
  /// returns its items plus the server's pagination meta — no up-front full-catalog
  /// sweep. The listing calls this per page as the customer scrolls (real paging).
  ///
  /// Meta is read from the paginated envelope's `meta` block, which the backend
  /// renderer camelCases to `{page, pageSize, total, totalPages}`; [Paginated] /
  /// [PageMeta] carry the parsed page state on to the controller.
  Future<Paginated<Product>> _fetchPage(
    String path,
    Map<String, dynamic> baseQuery, {
    required int page,
    required int pageSize,
  }) async {
    final res = await _client.get<dynamic>(
      path,
      query: {...baseQuery, 'page': page, 'page_size': pageSize},
      options: ApiClient.noAuth(),
    );
    final items = _list(res.data).map(_toProduct).toList();
    final rawMeta = res.data is Map ? res.data['meta'] : null;
    final meta = rawMeta is Map ? Map<String, dynamic>.from(rawMeta) : const {};
    int metaInt(String key, int fallback) {
      final v = meta[key];
      return v is num ? v.toInt() : fallback;
    }

    return Paginated<Product>(
      items: items,
      meta: PageMeta(
        currentPage: metaInt('page', page),
        lastPage: metaInt('totalPages', _totalPages(res.data)),
        perPage: metaInt('pageSize', pageSize),
        total: metaInt('total', items.length),
      ),
    );
  }

  // ---- endpoints ----
  @override
  Future<List<Category>> getDepartments() async {
    final res = await _client.get<dynamic>('/categories', options: ApiClient.noAuth());
    return _list(res.data).map(_toCategory).toList();
  }

  @override
  Future<List<Category>> getCategories({String? parentId}) async {
    if (parentId == null) return getDepartments();
    final res = await _client.get<dynamic>(
      '/categories/$parentId/sub-categories',
      options: ApiClient.noAuth(),
    );
    return _list(res.data).map(_toCategory).toList();
  }

  @override
  Future<List<Category>> getStoreCategories({String? parentId}) async {
    // Location scope matters here: the backend resolves the serving store from it
    // and the tree is that store's own products. Without it the response is
    // (correctly) empty rather than the global catalog.
    final res = await _client.get<dynamic>(
      '/store-categories',
      query: {if (parentId != null) 'parent': parentId, ..._scopeQuery},
      options: ApiClient.noAuth(),
    );
    return _list(res.data).map(_toCategory).toList();
  }

  @override
  Future<List<Product>> getStoreProducts({required String categoryId}) =>
      _fetchAllPages(
        '/products',
        {'category': categoryId, 'scope': 'private', ..._scopeQuery},
      );

  @override
  Future<List<Product>> getProducts({String? categoryId}) => _fetchAllPages(
        '/products',
        {if (categoryId != null) 'category': categoryId, ..._scopeQuery},
      );

  @override
  Future<Paginated<Product>> getProductsPage({
    String? categoryId,
    String? query,
    required int page,
    int pageSize = 20,
  }) {
    final q = (query ?? '').trim();
    if (q.isNotEmpty) {
      // Search results are their own (relevance-ordered) paginated endpoint.
      return _fetchPage(
        '/products/search',
        {'q': q, ..._scopeQuery},
        page: page,
        pageSize: pageSize,
      );
    }
    return _fetchPage(
      '/products',
      {if (categoryId != null) 'category': categoryId, ..._scopeQuery},
      page: page,
      pageSize: pageSize,
    );
  }

  @override
  Future<Product> getProductById(String id) async {
    // Carry the customer's location like every other catalog call: with
    // `zone_store_visibility` on, the detail endpoint scopes to the serving store
    // too, so a store-private product (and any deep link to it) 404s unless the
    // request resolves that store. Without this, detail relied solely on a saved
    // address and broke GPS-only browsing.
    final res = await _client.get<dynamic>(
      '/products/$id',
      query: _scopeQuery,
      options: ApiClient.noAuth(),
    );
    return _toProduct(_obj(res.data));
  }

  @override
  Future<List<Product>> getRecommended() async {
    final res = await _client.get<dynamic>(
      '/products',
      query: {'sort': 'rating', ..._scopeQuery, 'page_size': 10},
      options: ApiClient.noAuth(),
    );
    return _list(res.data).map(_toProduct).take(10).toList();
  }

  @override
  Future<List<Product>> getFeatured() async {
    // Highest-discount first, served by the backend in a single bounded page —
    // no full-catalog sweep just to surface 8 deals on the home cold-start.
    final res = await _client.get<dynamic>(
      '/products',
      query: {'sort': 'discount', ..._scopeQuery, 'page_size': 8},
      options: ApiClient.noAuth(),
    );
    return _list(res.data).map(_toProduct).take(8).toList();
  }

  @override
  Future<List<Product>> getPopular() async {
    // Most-reviewed first, one bounded page — the home "popular" rail no longer
    // pays a full-catalog walk to take(6).
    final res = await _client.get<dynamic>(
      '/products',
      query: {'sort': 'popular', ..._scopeQuery, 'page_size': 8},
      options: ApiClient.noAuth(),
    );
    return _list(res.data).map(_toProduct).take(8).toList();
  }

  @override
  Future<List<Product>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    return _fetchAllPages('/products/search', {'q': q, ..._scopeQuery});
  }

  @override
  Future<SearchSuggestions> suggest(String query) async {
    final q = query.trim();
    if (q.isEmpty) return SearchSuggestions.empty;
    final res = await _client.get<dynamic>(
      '/products/suggest',
      query: {'q': q, ..._scopeQuery},
      options: ApiClient.noAuth(),
    );
    final data = _obj(res.data);
    final products = (data['products'] as List?)
            ?.whereType<Map>()
            .map((e) => _toProduct(Map<String, dynamic>.from(e)))
            .toList() ??
        const <Product>[];
    final terms = (data['terms'] as List?)
            ?.map((e) => e.toString())
            .where((s) => s.trim().isNotEmpty)
            .toList() ??
        const <String>[];
    final categories = (data['categories'] as List?)
            ?.whereType<Map>()
            .map((e) => _toCategory(Map<String, dynamic>.from(e)))
            .toList() ??
        const <Category>[];
    return SearchSuggestions(
      products: products,
      terms: terms,
      categories: categories,
    );
  }

  // ---- mapping ----
  /// Resolve a host-root-relative media path (our catalog images come back as
  /// `/api/v1/media/public/<id>/<variant>`) to an absolute URL. Absolute URLs
  /// and bundled `assets/...` paths pass through unchanged. Done at ingestion so
  /// EVERY consumer — cards, gallery, and the non-widget cart fly-animation /
  /// precache that read the raw url — get a loadable URL.
  String? _abs(String? url) {
    if (url == null || url.isEmpty) return url;
    if (url.startsWith('assets/')) return url;
    return AppConfig.instance.assetUrl(url);
  }

  Category _toCategory(Map<String, dynamic> j) => Category(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        productCount: (j['productCount'] as num?)?.toInt() ?? 0,
        imageUrl: _abs(j['imageUrl'] as String?),
        iconName: j['iconName'] as String?,
        parentId: j['parentId']?.toString(),
        // Only the store-tree endpoint sends this; absent elsewhere → a leaf.
        hasChildren: j['hasChildren'] as bool? ?? false,
      );

  Product _toProduct(Map<String, dynamic> j) {
    final images = (j['images'] as List?)
            ?.map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .map((s) => _abs(s)!)
            .toList() ??
        const <String>[];
    final variants = (j['variants'] as List?)
            ?.whereType<Map>()
            .map((e) => _toVariant(Map<String, dynamic>.from(e)))
            .toList() ??
        const <ProductVariant>[];
    final specs = <String, String>{};
    final rawSpecs = j['specifications'];
    if (rawSpecs is Map) {
      rawSpecs.forEach((k, v) {
        if (v != null && v.toString().trim().isNotEmpty) {
          specs[k.toString()] = v.toString();
        }
      });
    }
    return Product(
      id: j['id'].toString(),
      shareToken: (j['shareToken'] ?? j['share_token']) as String?,
      name: (j['name'] ?? '').toString(),
      brand: (j['brand'] ?? '').toString(),
      unit: (j['unit'] ?? 'Each').toString(),
      price: (j['price'] as num?) ?? 0,
      mrp: (j['mrp'] as num?) ?? (j['price'] as num?) ?? 0,
      categoryId: (j['categoryId'] ?? '').toString(),
      creditPrice: j['creditPrice'] as num?,
      rating: (j['rating'] as num?)?.toDouble() ?? 0,
      reviews: (j['reviews'] as num?)?.toInt() ?? 0,
      imageUrl: _abs(j['imageUrl'] as String?),
      images: images,
      inStock: j['inStock'] as bool? ?? true,
      // Prefer sellable availability (on-hand − reserved) for low/out-of-stock UI;
      // fall back to physical on-hand when the field is absent.
      stockCount: (j['availableQuantity'] as num?)?.toInt() ??
          (j['stockCount'] as num?)?.toInt(),
      description: j['description'] as String?,
      variants: variants,
      specifications: specs,
    );
  }

  ProductVariant _toVariant(Map<String, dynamic> j) => ProductVariant(
        id: j['id'].toString(),
        label: (j['label'] ?? '').toString(),
        priceDelta: (j['priceDelta'] as num?) ?? 0,
        // The API resolves each pack's own price/MRP, its own photo, and its own
        // per-store sellable count. Dropping these (as this mapper used to) made
        // packs show the product's MRP, never their own image, and gate stock on
        // the coarse inStock flag instead of the real available count.
        price: j['price'] as num?,
        mrp: j['mrp'] as num?,
        imageUrl: _abs(j['imageUrl'] as String?),
        available: (j['available'] as num?)?.toInt(),
        inStock: j['inStock'] as bool? ?? true,
      );
}

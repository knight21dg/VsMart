import '../../../../core/network/api_client.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_variant.dart';
import 'catalog_data_source.dart';

/// [CatalogDataSource] backed by the VS Mart backend (`/api/v1`). Unwraps the
/// `{ success, message, data, meta }` envelope and maps the backend's camelCase
/// product/category JSON onto the catalog domain entities.
///
/// Wrapped by [CachingCatalogDataSource], so responses are cached for offline use.
class BackendCatalogDataSource implements CatalogDataSource {
  BackendCatalogDataSource(this._client, {this.storeId});

  final ApiClient _client;

  /// The serviceable store id for the customer's current zone, if resolved.
  /// Sent as `?store=` so the backend can scope the catalog to that store's
  /// inventory — a no-op until the backend `zone_store_visibility` flag is on.
  final String? storeId;

  Map<String, dynamic> get _storeQuery =>
      storeId == null ? const {} : {'store': storeId};

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
  Future<List<Product>> getProducts({String? categoryId}) => _fetchAllPages(
        '/products',
        {if (categoryId != null) 'category': categoryId, ..._storeQuery},
      );

  @override
  Future<Product> getProductById(String id) async {
    final res =
        await _client.get<dynamic>('/products/$id', options: ApiClient.noAuth());
    return _toProduct(_obj(res.data));
  }

  @override
  Future<List<Product>> getRecommended() async {
    final res = await _client.get<dynamic>(
      '/products',
      query: {'sort': 'rating', ..._storeQuery, 'page_size': 10},
      options: ApiClient.noAuth(),
    );
    return _list(res.data).map(_toProduct).take(10).toList();
  }

  @override
  Future<List<Product>> getFeatured() async {
    final products = await _fetchAllPages('/products', {..._storeQuery})
      ..sort((a, b) => b.discountPercent.compareTo(a.discountPercent));
    return products.take(8).toList();
  }

  @override
  Future<List<Product>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    return _fetchAllPages('/products/search', {'q': q, ..._storeQuery});
  }

  // ---- mapping ----
  Category _toCategory(Map<String, dynamic> j) => Category(
        id: j['id'].toString(),
        name: (j['name'] ?? '').toString(),
        productCount: (j['productCount'] as num?)?.toInt() ?? 0,
        imageUrl: j['imageUrl'] as String?,
        iconName: j['iconName'] as String?,
        parentId: j['parentId']?.toString(),
      );

  Product _toProduct(Map<String, dynamic> j) {
    final images = (j['images'] as List?)
            ?.map((e) => e.toString())
            .where((s) => s.isNotEmpty)
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
      name: (j['name'] ?? '').toString(),
      brand: (j['brand'] ?? '').toString(),
      unit: (j['unit'] ?? 'Each').toString(),
      price: (j['price'] as num?) ?? 0,
      mrp: (j['mrp'] as num?) ?? (j['price'] as num?) ?? 0,
      categoryId: (j['categoryId'] ?? '').toString(),
      creditPrice: j['creditPrice'] as num?,
      rating: (j['rating'] as num?)?.toDouble() ?? 0,
      reviews: (j['reviews'] as num?)?.toInt() ?? 0,
      imageUrl: j['imageUrl'] as String?,
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
        inStock: j['inStock'] as bool? ?? true,
      );
}

/// Cursor/offset pagination metadata returned in an API response `meta` block.
class PageMeta {
  const PageMeta({
    required this.currentPage,
    required this.lastPage,
    required this.perPage,
    required this.total,
  });

  final int currentPage;
  final int lastPage;
  final int perPage;
  final int total;

  bool get hasMore => currentPage < lastPage;
  int get nextPage => currentPage + 1;

  factory PageMeta.fromJson(Map<String, dynamic> json) {
    int read(String a, String b, [int fallback = 0]) =>
        (json[a] ?? json[b] ?? fallback) as int;
    return PageMeta(
      currentPage: read('current_page', 'currentPage', 1),
      lastPage: read('last_page', 'lastPage', 1),
      perPage: read('per_page', 'perPage', 20),
      total: read('total', 'total'),
    );
  }

  static const PageMeta empty =
      PageMeta(currentPage: 1, lastPage: 1, perPage: 20, total: 0);
}

/// A page of items plus its [meta]. Generic over the item type [T].
class Paginated<T> {
  const Paginated({required this.items, required this.meta});

  final List<T> items;
  final PageMeta meta;

  bool get hasMore => meta.hasMore;
  int get nextPage => meta.nextPage;

  factory Paginated.fromJson(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromItem,
  ) {
    final list = (json['data'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(fromItem)
        .toList();
    final meta = json['meta'] is Map<String, dynamic>
        ? PageMeta.fromJson(json['meta'] as Map<String, dynamic>)
        : PageMeta.empty;
    return Paginated<T>(items: list, meta: meta);
  }

  Paginated<T> copyWith({List<T>? items, PageMeta? meta}) =>
      Paginated<T>(items: items ?? this.items, meta: meta ?? this.meta);

  /// Merge a newly fetched page onto this one (for infinite scroll).
  Paginated<T> append(Paginated<T> next) =>
      Paginated<T>(items: [...items, ...next.items], meta: next.meta);
}

/// Standard query params for paginated list endpoints.
class PageRequest {
  const PageRequest({this.page = 1, this.perPage = 20, this.query});

  final int page;
  final int perPage;
  final String? query;

  Map<String, dynamic> toQuery() => {
        'page': page,
        'per_page': perPage,
        if (query != null && query!.isNotEmpty) 'q': query,
      };
}

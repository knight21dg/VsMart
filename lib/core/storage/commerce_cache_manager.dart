import 'hive_service.dart';

/// Generic JSON-list cache over Hive boxes, used by the commerce caching data
/// sources to implement stale-while-revalidate. Each entry stores the payload
/// plus a `cachedAt` timestamp so freshness can be evaluated.
class CommerceCacheManager {
  CommerceCacheManager(this._hive);

  final HiveService _hive;

  /// Read a cached list for [key] from the named [boxName], or null if absent.
  List<Map<String, dynamic>>? readList(String boxName, String key) {
    final raw = _hive.box(boxName).get(key);
    if (raw is Map && raw['data'] is List) {
      return (raw['data'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return null;
  }

  /// Persist [data] under [key] with the current timestamp.
  Future<void> writeList(
    String boxName,
    String key,
    List<Map<String, dynamic>> data,
  ) {
    return _hive.box(boxName).put(key, {
      'data': data,
      'cachedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// When [key] was last cached, or null if never.
  DateTime? cachedAt(String boxName, String key) {
    final raw = _hive.box(boxName).get(key);
    if (raw is Map && raw['cachedAt'] is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw['cachedAt'] as int);
    }
    return null;
  }

  /// Whether the cached entry for [key] is within [ttl].
  bool isFresh(String boxName, String key, Duration ttl) {
    final at = cachedAt(boxName, key);
    if (at == null) return false;
    return DateTime.now().difference(at) < ttl;
  }
}

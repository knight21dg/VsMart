import 'dart:convert';

import 'hive_service.dart';

/// Simple TTL-based offline cache backed by the Hive cache box.
///
/// Entries store `{ "ts": epochMs, "ttl": ms, "data": <json> }`. Reads return
/// `null` for missing or expired entries.
class CacheManager {
  CacheManager(this._hive);

  final HiveService _hive;

  static const Duration defaultTtl = Duration(hours: 6);

  Future<void> write(
    String key,
    Object? jsonEncodable, {
    Duration ttl = defaultTtl,
  }) async {
    final entry = {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'ttl': ttl.inMilliseconds,
      'data': jsonEncode(jsonEncodable),
    };
    await _hive.cacheBox.put(key, entry);
  }

  /// Read a cached value, or `null` if missing/expired.
  dynamic read(String key) {
    final raw = _hive.cacheBox.get(key);
    if (raw is! Map) return null;

    final ts = raw['ts'] as int? ?? 0;
    final ttl = raw['ttl'] as int? ?? 0;
    final expired =
        DateTime.now().millisecondsSinceEpoch - ts > ttl;
    if (expired) {
      _hive.cacheBox.delete(key);
      return null;
    }
    final data = raw['data'];
    return data is String ? jsonDecode(data) : data;
  }

  bool has(String key) => read(key) != null;

  Future<void> invalidate(String key) => _hive.cacheBox.delete(key);

  Future<void> clear() => _hive.cacheBox.clear();
}

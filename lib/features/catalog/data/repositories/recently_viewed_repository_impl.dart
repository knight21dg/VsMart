import '../../../../core/storage/hive_service.dart';
import '../../domain/entities/recently_viewed_entry.dart';
import '../../domain/repositories/recently_viewed_repository.dart';

/// [RecentlyViewedRepository] backed by the Hive `recentlyViewedBox`. Stored as
/// a most-recent-first list of `{productId, viewedAt}` maps, capped at [_max].
class RecentlyViewedRepositoryImpl implements RecentlyViewedRepository {
  RecentlyViewedRepositoryImpl(this._hive);

  final HiveService _hive;

  static const _key = 'entries';
  static const _max = 20;

  List<RecentlyViewedEntry> _read() {
    final raw = _hive.recentlyViewedBox.get(_key);
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => RecentlyViewedEntry(
                productId: e['productId'] as String? ?? '',
                viewedAt: DateTime.fromMillisecondsSinceEpoch(
                    (e['viewedAt'] as num?)?.toInt() ?? 0),
              ))
          .where((e) => e.productId.isNotEmpty)
          .toList();
    }
    return [];
  }

  Future<List<RecentlyViewedEntry>> _write(List<RecentlyViewedEntry> entries) async {
    final capped = entries.take(_max).toList();
    await _hive.recentlyViewedBox.put(
      _key,
      capped
          .map((e) => {
                'productId': e.productId,
                'viewedAt': e.viewedAt.millisecondsSinceEpoch,
              })
          .toList(),
    );
    return List.unmodifiable(capped);
  }

  @override
  List<RecentlyViewedEntry> getRecent() => List.unmodifiable(_read());

  @override
  Future<List<RecentlyViewedEntry>> addViewed(String productId) async {
    final entries = _read()..removeWhere((e) => e.productId == productId);
    entries.insert(
      0,
      RecentlyViewedEntry(productId: productId, viewedAt: DateTime.now()),
    );
    return _write(entries);
  }

  @override
  Future<List<RecentlyViewedEntry>> removeViewed(String productId) async {
    final entries = _read()..removeWhere((e) => e.productId == productId);
    return _write(entries);
  }

  @override
  Future<void> clear() => _hive.recentlyViewedBox.delete(_key);
}

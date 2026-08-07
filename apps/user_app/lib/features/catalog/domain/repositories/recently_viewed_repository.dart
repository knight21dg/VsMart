import '../entities/recently_viewed_entry.dart';

/// Local store of recently-viewed products (most recent first, capped). Powers
/// Continue Shopping, Home, and recommendations.
abstract interface class RecentlyViewedRepository {
  /// Recent entries, most-recent first.
  List<RecentlyViewedEntry> getRecent();

  /// Record a view (de-duplicated; refreshes the timestamp if already present).
  Future<List<RecentlyViewedEntry>> addViewed(String productId);

  /// Remove a product from the history.
  Future<List<RecentlyViewedEntry>> removeViewed(String productId);

  /// Clear the entire history.
  Future<void> clear();
}

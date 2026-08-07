import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/offer_backend_data_source.dart';
import 'offer_providers.dart';

/// App-wide sink that batches banner impression/click events and flushes them to
/// `/offers/events`. Impressions are de-duplicated per offer for the lifetime of
/// the sink (one impression per banner per session) so CTR isn't inflated by the
/// auto-scrolling carousel revisiting the same banner.
///
/// The data source is read LAZILY (ref.read at flush time) rather than watched, so
/// changing the delivery address — which rebuilds offerRemoteDataSourceProvider —
/// does NOT recreate the sink and wipe its impression-dedup memory.
final bannerEventSinkProvider = Provider<BannerEventSink>((ref) {
  final sink = BannerEventSink(() {
    final source = ref.read(offerRemoteDataSourceProvider);
    return source is OfferBackendDataSource ? source : null;
  });
  ref.onDispose(sink.dispose);
  return sink;
});

class BannerEventSink {
  BannerEventSink(this._source);

  final OfferBackendDataSource? Function() _source;
  final Set<String> _seenImpressions = {};
  final List<Map<String, dynamic>> _buffer = [];
  Timer? _flushTimer;

  /// Record a banner becoming visible (once per offer per session).
  void impression(String offerId) {
    if (offerId.isEmpty || !_seenImpressions.add(offerId)) return;
    _add({'offer_id': offerId, 'kind': 'impression'});
  }

  /// Record a banner tap and flush promptly.
  void click(String offerId) {
    if (offerId.isEmpty) return;
    _add({'offer_id': offerId, 'kind': 'click'});
    _flush();
  }

  void _add(Map<String, dynamic> event) {
    _buffer.add(event);
    if (_buffer.length >= 20) {
      _flush();
    } else {
      _flushTimer ??= Timer(const Duration(seconds: 3), _flush);
    }
  }

  void _flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_buffer.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    _source()?.sendEvents(batch);
  }

  void dispose() {
    _flush();
    _flushTimer?.cancel();
  }
}

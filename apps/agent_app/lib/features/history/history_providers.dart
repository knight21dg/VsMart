import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'history_data.dart';

final historyApiProvider = Provider<HistoryApi>(
  (ref) => HistoryApi(ref.watch(apiProvider)),
);

/// Which slice of history is on screen. Changing this reloads from page 0.
class HistoryFilter extends Equatable {
  const HistoryFilter({this.kind, this.from, this.to});

  final HistoryKind? kind;   // null = every kind
  final DateTime? from;
  final DateTime? to;

  HistoryFilter withKind(HistoryKind? k) =>
      HistoryFilter(kind: k, from: from, to: to);

  HistoryFilter withRange(DateTime? f, DateTime? t) =>
      HistoryFilter(kind: kind, from: f, to: t);

  bool get hasRange => from != null || to != null;

  @override
  List<Object?> get props => [kind, from, to];
}

final historyFilterProvider =
    StateProvider.autoDispose<HistoryFilter>((_) => const HistoryFilter());

/// Accumulated pages for the current filter.
class HistoryState extends Equatable {
  const HistoryState({
    this.items = const [],
    this.counts = const {},
    this.total = 0,
    this.collectedTotal = 0,
    this.hasMore = false,
    this.loading = true,
    this.loadingMore = false,
    this.error,
  });

  final List<HistoryEntry> items;
  final Map<String, int> counts;
  final int total;
  final num collectedTotal;
  final bool hasMore;
  final bool loading;
  final bool loadingMore;
  final Object? error;

  bool get isEmpty => !loading && error == null && items.isEmpty;

  HistoryState copyWith({
    List<HistoryEntry>? items,
    Map<String, int>? counts,
    int? total,
    num? collectedTotal,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool clearError = false,
  }) =>
      HistoryState(
        items: items ?? this.items,
        counts: counts ?? this.counts,
        total: total ?? this.total,
        collectedTotal: collectedTotal ?? this.collectedTotal,
        hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props =>
      [items, total, collectedTotal, hasMore, loading, loadingMore, error];
}

class HistoryController extends StateNotifier<HistoryState> {
  HistoryController(this._api, this._filter) : super(const HistoryState()) {
    refresh();
  }

  final HistoryApi _api;
  final HistoryFilter _filter;

  /// Guards against a second load firing while one is in flight — the scroll
  /// listener can trip repeatedly before the first page lands, which would
  /// append the same rows twice.
  bool _busy = false;

  Future<void> refresh() async {
    if (_busy) return;
    _busy = true;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final page = await _fetch(0);
      state = HistoryState(
        items: page.items,
        counts: page.counts,
        total: page.total,
        collectedTotal: page.collectedTotal,
        hasMore: page.hasMore,
        loading: false,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: e);
    } finally {
      _busy = false;
    }
  }

  Future<void> loadMore() async {
    if (_busy || !state.hasMore || state.loading) return;
    _busy = true;
    state = state.copyWith(loadingMore: true);
    try {
      final page = await _fetch(state.items.length);
      state = state.copyWith(
        items: [...state.items, ...page.items],
        hasMore: page.hasMore,
        loadingMore: false,
      );
    } catch (e) {
      // Keep the rows already on screen; surface the failure without wiping
      // what the agent was reading.
      state = state.copyWith(loadingMore: false, error: e);
    } finally {
      _busy = false;
    }
  }

  Future<HistoryPage> _fetch(int offset) => _api.fetch(
        kind: _filter.kind,
        from: _filter.from,
        to: _filter.to,
        offset: offset,
      );
}

/// The few most recent closed tasks, for the dashboard activity feed.
/// Separate from [historyControllerProvider] so the feed is unaffected by
/// whatever filter the full history screen happens to be showing.
final recentHistoryProvider = FutureProvider.autoDispose<List<HistoryEntry>>(
  (ref) async {
    final page = await ref.watch(historyApiProvider).fetch(limit: 5);
    return page.items;
  },
);

/// Rebuilds (and reloads from page 0) whenever the filter changes.
final historyControllerProvider =
    StateNotifierProvider.autoDispose<HistoryController, HistoryState>((ref) {
  return HistoryController(
    ref.watch(historyApiProvider),
    ref.watch(historyFilterProvider),
  );
});

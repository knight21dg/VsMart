import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/constants/storage_keys.dart';
import '../../../../shared/providers/core_providers.dart';

/// The live search query (updated, debounced, by the search field).
final searchQueryProvider = StateProvider<String>((ref) => '');

/// Persisted recent search terms (most-recent first), capped at [_max].
class RecentSearchesController extends Notifier<List<String>> {
  static const _max = 8;

  @override
  List<String> build() {
    final raw = ref
        .read(hiveServiceProvider)
        .settingsBox
        .get(StorageKeys.recentSearches, defaultValue: const <dynamic>[]);
    return (raw as List).cast<String>();
  }

  Future<void> add(String term) async {
    final t = term.trim();
    if (t.isEmpty) return;
    final next = [t, ...state.where((e) => e.toLowerCase() != t.toLowerCase())]
        .take(_max)
        .toList();
    state = next;
    await _persist();
  }

  Future<void> remove(String term) async {
    state = state.where((e) => e != term).toList();
    await _persist();
  }

  Future<void> clear() async {
    state = const [];
    await _persist();
  }

  Future<void> _persist() => ref
      .read(hiveServiceProvider)
      .settingsBox
      .put(StorageKeys.recentSearches, state);
}

final recentSearchesProvider =
    NotifierProvider<RecentSearchesController, List<String>>(
        RecentSearchesController.new);

/// Static trending terms shown before the user types.
const trendingSearches = <String>[
  'Atta',
  'Cooking Oil',
  'Milk',
  'Basmati Rice',
  'Sugar',
  'Tea',
  'Eggs',
  'Biscuits',
];

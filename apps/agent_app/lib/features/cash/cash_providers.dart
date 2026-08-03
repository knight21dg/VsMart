import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'cash_data.dart';

final cashApiProvider = Provider<CashApi>(
  (ref) => CashApi(ref.watch(apiProvider)),
);

/// What the signed-in agent is holding, plus their hand-over history
/// (GET /agent/cash).
final cashSummaryProvider = FutureProvider.autoDispose<CashSummary>(
  (ref) => ref.watch(cashApiProvider).fetch(),
);

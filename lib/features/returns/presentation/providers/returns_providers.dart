import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/core_providers.dart';
import '../../data/returns_data.dart';

final returnsDataSourceProvider = Provider<ReturnsRemoteDataSource>(
  (ref) => ReturnsRemoteDataSource(ref.watch(apiClientProvider)),
);

/// The signed-in customer's return / refund requests.
final returnsProvider = FutureProvider<List<ReturnRequest>>(
  (ref) => ref.watch(returnsDataSourceProvider).list(),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/core_providers.dart';
import '../../data/family_data.dart';

final familyDataSourceProvider = Provider<FamilyRemoteDataSource>(
  (ref) => FamilyRemoteDataSource(ref.watch(apiClientProvider)),
);

/// The signed-in user's family group (shared limit + members).
final familyGroupProvider = FutureProvider<FamilyGroupModel>(
  (ref) => ref.watch(familyDataSourceProvider).getFamily(),
);

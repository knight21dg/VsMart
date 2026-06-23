import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/core_providers.dart';
import '../../data/referral_data.dart';

final referralDataSourceProvider = Provider<ReferralRemoteDataSource>(
  (ref) => ReferralRemoteDataSource(ref.watch(apiClientProvider)),
);

/// The signed-in user's referral code, reward and completed-referral count.
final referralProvider = FutureProvider<ReferralInfo>(
  (ref) => ref.watch(referralDataSourceProvider).getReferral(),
);

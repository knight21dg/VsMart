import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/kyc_data.dart';

final kycRepoProvider = Provider<KycRepo>(
  (ref) => KycRepo(ref.watch(apiProvider)),
);

/// Pending KYC applications awaiting agent field verification.
final kycQueueProvider =
    FutureProvider.autoDispose<List<KycApplicationModel>>(
  (ref) => ref.watch(kycRepoProvider).queue(),
);

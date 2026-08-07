import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/constants/api_constants.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../auth/presentation/providers/session_provider.dart';
import '../../domain/entities/credit_application.dart';

/// The customer's current credit application, or null if they've never applied.
///
/// Kept separate from the KYC/verification providers on purpose: identity
/// verification and a credit application are different submissions with
/// different decisions behind them.
final creditApplicationProvider =
    FutureProvider<CreditApplication?>((ref) async {
  // Re-fetch on sign-in/out so one customer never sees another's application.
  ref.watch(authStatusProvider);
  final client = ref.watch(apiClientProvider);
  final res = await client.get<dynamic>(ApiConstants.creditApplication);
  final raw = res.data;
  final data = raw is Map && raw['data'] != null ? raw['data'] : raw;
  if (data is! Map || data.isEmpty) return null; // never applied
  return CreditApplication.fromJson(Map<String, dynamic>.from(data));
});

/// Submits (or resubmits) a credit application.
class CreditApplicationController {
  CreditApplicationController(this._ref);

  final Ref _ref;

  /// POSTs the application. Throws on failure so the caller can surface the
  /// server's actionable code (e.g. KYC_REQUIRED, CREDIT_APPLICATION_IN_REVIEW).
  Future<CreditApplication> submit({
    required String occupation,
    required num monthlyIncome,
    required int familyMembers,
    required String houseType,
    required String ownership,
    required num requestedLimit,
  }) async {
    final client = _ref.read(apiClientProvider);
    final res = await client.post<dynamic>(
      ApiConstants.creditApply,
      data: {
        'occupation': occupation,
        'monthlyIncome': monthlyIncome,
        'familyMembers': familyMembers,
        'houseType': houseType,
        'ownership': ownership,
        'requestedLimit': requestedLimit,
      },
    );
    final raw = res.data;
    final data = raw is Map && raw['data'] != null ? raw['data'] : raw;
    _ref.invalidate(creditApplicationProvider);
    return CreditApplication.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> withdraw() async {
    await _ref
        .read(apiClientProvider)
        .post<dynamic>(ApiConstants.creditApplicationWithdraw, data: const {});
    _ref.invalidate(creditApplicationProvider);
  }
}

final creditApplicationControllerProvider =
    Provider<CreditApplicationController>(CreditApplicationController.new);

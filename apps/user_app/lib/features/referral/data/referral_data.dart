import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

import '../../../app/constants/api_constants.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/api_client.dart';

/// The signed-in user's referral standing, from `GET /referrals`.
class ReferralInfo extends Equatable {
  const ReferralInfo({
    required this.code,
    required this.reward,
    required this.referredCount,
    this.status = 'pending',
  });

  final String code;

  /// Wallet credit earned per successful referral (₹).
  final num reward;

  /// How many invitees have completed a referral.
  final int referredCount;
  final String status;

  @override
  List<Object?> get props => [code, reward, referredCount, status];
}

/// Outcome of applying someone else's referral code.
class ApplyReferralResult extends Equatable {
  const ApplyReferralResult({
    required this.ok,
    required this.reward,
    required this.message,
  });

  final bool ok;
  final num reward;
  final String message;

  @override
  List<Object?> get props => [ok, reward, message];
}

/// Backend referrals API: `/referrals`, `/referrals/apply`.
class ReferralRemoteDataSource {
  ReferralRemoteDataSource(this._client);

  final ApiClient _client;

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  num _num(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

  Future<ReferralInfo> getReferral() async {
    final res = await _client.get<dynamic>(ApiConstants.referrals);
    final j = _obj(res.data);
    return ReferralInfo(
      code: (j['code'] ?? '').toString(),
      reward: _num(j['reward']),
      referredCount: (j['referredCount'] as num?)?.toInt() ?? 0,
      status: (j['status'] ?? 'pending').toString(),
    );
  }

  Future<ApplyReferralResult> applyCode(String code) async {
    try {
      final res = await _client.post<dynamic>(
        ApiConstants.referralsApply,
        data: {'code': code},
      );
      final inner = _obj(res.data);
      return ApplyReferralResult(
        ok: true,
        reward: _num(inner['reward']),
        message: 'Referral code applied',
      );
    } on DioException catch (e) {
      // A 4xx (already applied / invalid code) carries the backend's real
      // message on the typed Failure.
      final failure = e.error is Failure ? e.error as Failure : null;
      return ApplyReferralResult(
        ok: false,
        reward: 0,
        message: failure?.message ?? 'Invalid referral code',
      );
    }
  }
}

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

import '../../../app/constants/api_constants.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/errors/failures.dart';
import '../../../core/network/api_client.dart';

/// The signed-in user's reward-points standing, from `GET /loyalty`.
class LoyaltyStatus extends Equatable {
  const LoyaltyStatus({
    required this.balance,
    required this.lifetimeEarned,
    required this.tier,
  });

  /// Points currently available to redeem.
  final int balance;

  /// Total points ever earned (never decreases).
  final int lifetimeEarned;

  /// Membership tier label (e.g. "Silver", "Gold").
  final String tier;

  @override
  List<Object?> get props => [balance, lifetimeEarned, tier];
}

/// A single line in the points ledger, from `GET /loyalty/ledger`.
class PointsEntry extends Equatable {
  const PointsEntry({
    required this.id,
    required this.type,
    required this.points,
    required this.balanceAfter,
    required this.note,
    required this.date,
  });

  final String id;

  /// One of `earn`, `redeem`, `expire`.
  final String type;

  /// Signed change for this entry (positive for earn, negative for redeem).
  final int points;

  /// Running balance after this entry was applied.
  final int balanceAfter;
  final String note;
  final DateTime date;

  @override
  List<Object?> get props => [id, type, points, balanceAfter, note, date];
}

/// Backend loyalty API: `/loyalty`, `/loyalty/ledger`, `/loyalty/redeem`.
class LoyaltyRemoteDataSource {
  LoyaltyRemoteDataSource(this._client);

  final ApiClient _client;

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  List<dynamic> _list(dynamic raw) {
    final data = raw is Map && raw['data'] is List ? raw['data'] : raw;
    return data is List ? data : const <dynamic>[];
  }

  num _num(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

  int _int(dynamic v) => _num(v).toInt();

  /// Builds the Idempotency-Key header. Prefer a caller-supplied [key] that is
  /// stable across retries of the SAME logical redeem — a fresh timestamp per
  /// call would defeat idempotency (a timed-out retry would redeem twice). Falls
  /// back to a generated key only when no key is passed.
  Options _idem(String prefix, [String? key]) => Options(
        headers: {
          'Idempotency-Key':
              key ?? '${prefix}_${DateTime.now().microsecondsSinceEpoch}',
        },
      );

  DateTime _date(dynamic v) =>
      DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.now();

  Future<LoyaltyStatus> getStatus() async {
    final res = await _client.get<dynamic>(ApiConstants.loyalty);
    final j = _obj(res.data);
    return LoyaltyStatus(
      balance: _int(j['balance']),
      lifetimeEarned: _int(j['lifetimeEarned']),
      tier: (j['tier'] ?? '').toString(),
    );
  }

  Future<List<PointsEntry>> getLedger() async {
    final res = await _client.get<dynamic>(ApiConstants.loyaltyLedger);
    return _list(res.data).whereType<Map>().map((raw) {
      final j = Map<String, dynamic>.from(raw);
      return PointsEntry(
        id: (j['id'] ?? '').toString(),
        type: (j['type'] ?? '').toString(),
        points: _int(j['points']),
        balanceAfter: _int(j['balanceAfter']),
        note: (j['note'] ?? '').toString(),
        date: _date(j['createdAt']),
      );
    }).toList();
  }

  /// Redeems [points]. A 4xx (e.g. insufficient points) raises a DioException
  /// carrying the typed [Failure] with the backend's real message — surfaced
  /// to the caller as `ok:false` (with the [Failure]) instead of a misleading
  /// success, so the UI can route it through the actionable error presenter.
  Future<({bool ok, String message, num balance, Failure? failure})> redeem(
    int points, {
    String? idempotencyKey,
  }) async {
    try {
      final res = await _client.post<dynamic>(
        ApiConstants.loyaltyRedeem,
        data: {'points': points},
        options: _idem('redeem', idempotencyKey),
      );
      final inner = _obj(res.data);
      final redeemed = _int(inner['redeemed']);
      return (
        ok: true,
        message: redeemed > 0 ? 'Redeemed $redeemed points' : 'Points redeemed',
        balance: _num(inner['balance']),
        failure: null,
      );
    } catch (e) {
      final failure = (e is DioException && e.error is Failure)
          ? e.error as Failure
          : ErrorHandler.handle(e);
      return (
        ok: false,
        message: failure.message,
        balance: 0,
        failure: failure,
      );
    }
  }
}

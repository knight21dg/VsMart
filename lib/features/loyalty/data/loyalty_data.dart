import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

import '../../../app/constants/api_constants.dart';
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
  /// to the caller as `ok:false` instead of a misleading success.
  Future<({bool ok, String message, num balance})> redeem(int points) async {
    try {
      final res = await _client.post<dynamic>(
        ApiConstants.loyaltyRedeem,
        data: {'points': points},
      );
      final inner = _obj(res.data);
      final redeemed = _int(inner['redeemed']);
      return (
        ok: true,
        message: redeemed > 0 ? 'Redeemed $redeemed points' : 'Points redeemed',
        balance: _num(inner['balance']),
      );
    } on DioException catch (e) {
      final failure = e.error is Failure ? e.error as Failure : null;
      return (
        ok: false,
        message: failure?.message ?? 'Could not redeem points',
        balance: 0,
      );
    }
  }
}

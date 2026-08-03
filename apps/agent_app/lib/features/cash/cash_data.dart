import 'package:equatable/equatable.dart';

import '../../core/api.dart';

num _num(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

String _str(dynamic v) => v == null ? '' : v.toString();

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// A collection whose cash the agent is still holding.
class HeldCollection extends Equatable {
  const HeldCollection({
    required this.id,
    required this.customerName,
    required this.amount,
    this.collectedAt,
  });

  final String id;
  final String customerName;
  final num amount;
  final DateTime? collectedAt;

  factory HeldCollection.fromJson(Map<String, dynamic> j) => HeldCollection(
        id: _str(j['id']),
        customerName: _str(j['customerName'] ?? j['customer_name']),
        amount: _num(j['collectedAmount'] ?? j['collected_amount']),
        collectedAt: _date(j['collectedAt'] ?? j['collected_at']),
      );

  @override
  List<Object?> get props => [id, customerName, amount, collectedAt];
}

/// How a declared hand-over is progressing.
enum DepositStatus {
  initiated('initiated', 'Awaiting payment'),
  pending('pending', 'Awaiting count'),
  verified('verified', 'Received'),
  short('short', 'Short'),
  rejected('rejected', 'Rejected'),
  cancelled('cancelled', 'Cancelled');

  const DepositStatus(this.code, this.label);
  final String code;
  final String label;

  static DepositStatus parse(String? v) => DepositStatus.values.firstWhere(
        (s) => s.code == v,
        orElse: () => DepositStatus.pending,
      );
}

/// A cash hand-over the agent declared.
class CashDeposit extends Equatable {
  const CashDeposit({
    required this.id,
    required this.amount,
    required this.method,
    required this.channel,
    required this.status,
    this.depositedOn,
    this.reference = '',
    this.verifiedAmount,
    this.shortfall = 0,
    this.notes = '',
  });

  final String id;
  final num amount;
  final String method;

  /// 'online' (a gateway-verified digital transfer) or 'cash' (physical notes).
  final String channel;
  final DepositStatus status;
  final DateTime? depositedOn;
  final String reference;
  final num? verifiedAmount;
  final num shortfall;
  final String notes;

  bool get isOnline => channel == 'online';

  factory CashDeposit.fromJson(Map<String, dynamic> j) => CashDeposit(
        id: _str(j['id']),
        amount: _num(j['amount']),
        method: _str(j['method']),
        channel: _str(j['channel']).isEmpty ? 'cash' : _str(j['channel']),
        status: DepositStatus.parse(_str(j['status'])),
        depositedOn: _date(j['depositedOn'] ?? j['deposited_on']),
        reference: _str(j['reference']),
        // Bug: `a ?? b == null ? x : y` parses as `a ?? (b == null ? x : y)`
        // (`==` binds tighter than `??` in Dart) — so whenever `verifiedAmount`
        // was present it returned the RAW dynamic value, bypassing `_num()`.
        // The backend sends decimals as JSON strings (DRF's default
        // DecimalField behaviour, same as `amount`/`shortfall` below), so
        // assigning that raw string into this `num?` field threw a runtime
        // TypeError on every verified deposit — which is exactly what made
        // the Cash tab show "Could not load your cash" for any agent with at
        // least one verified hand-over.
        verifiedAmount: (j['verifiedAmount'] ?? j['verified_amount']) == null
            ? null
            : _num(j['verifiedAmount'] ?? j['verified_amount']),
        shortfall: _num(j['shortfall']),
        notes: _str(j['notes']),
      );

  @override
  List<Object?> get props =>
      [id, amount, method, channel, status, depositedOn, reference,
       verifiedAmount];
}

/// The result of starting an online hand-over: the deposit is reserved and a
/// Razorpay link is waiting to be paid.
class OnlineHandover extends Equatable {
  const OnlineHandover({
    required this.depositId,
    required this.paymentId,
    required this.shortUrl,
    required this.amount,
    required this.confirmed,
  });

  final String depositId;
  final String paymentId;
  final String shortUrl;
  final num amount;

  /// True when the gateway already reported the money received (a trusted mock,
  /// or an unusually fast confirmation), so there's nothing left to pay.
  final bool confirmed;

  @override
  List<Object?> get props => [depositId, paymentId, shortUrl, amount, confirmed];
}

/// Everything the agent's cash tab needs in one shot.
class CashSummary extends Equatable {
  const CashSummary({
    required this.inHand,
    required this.collections,
    required this.deposits,
  });

  final num inHand;
  final List<HeldCollection> collections;
  final List<CashDeposit> deposits;

  @override
  List<Object?> get props => [inHand, collections, deposits];
}

/// Cash hand-over API (`/agent/cash`).
///
/// Closes the last gap in the cash chain: an agent collects money from
/// customers, and this is how they record handing it over so it stops showing
/// as outstanding against them.
class CashApi {
  CashApi(this._api);

  final Api _api;

  Future<CashSummary> fetch() async {
    final res = await _api.get('/agent/cash');
    final data = _unwrap(res.data);
    return CashSummary(
      inHand: _num(data['inHand'] ?? data['in_hand']),
      collections: [
        for (final c in (data['collections'] as List? ?? const []))
          HeldCollection.fromJson(Map<String, dynamic>.from(c as Map)),
      ],
      deposits: [
        for (final d in (data['deposits'] as List? ?? const []))
          CashDeposit.fromJson(Map<String, dynamic>.from(d as Map)),
      ],
    );
  }

  /// Declare a hand-over. [collectionIds] ties it to the exact collections
  /// being banked so the same cash can never be deposited twice.
  Future<CashDeposit> declare({
    required num amount,
    required String method,
    required List<String> collectionIds,
    String reference = '',
    String notes = '',
  }) async {
    final res = await _api.post('/agent/cash', data: {
      'amount': amount,
      'method': method,
      'collectionIds': collectionIds,
      if (reference.isNotEmpty) 'reference': reference,
      if (notes.isNotEmpty) 'notes': notes,
    });
    return CashDeposit.fromJson(_unwrap(res.data));
  }

  /// Start an online hand-over: reserve [collectionIds] and raise a Razorpay
  /// link to send the money to the agent's store. The amount is computed
  /// server-side from the collections — the app never sends a figure.
  Future<OnlineHandover> declareOnline({
    required List<String> collectionIds,
  }) async {
    final res = await _api.post('/agent/cash/online', data: {
      'collectionIds': collectionIds,
    });
    final data = _unwrap(res.data);
    final payment = data['payment'] is Map
        ? Map<String, dynamic>.from(data['payment'] as Map)
        : <String, dynamic>{};
    return OnlineHandover(
      depositId: _str(data['id']),
      paymentId: _str(payment['paymentId'] ?? payment['payment_id']),
      shortUrl: _str(payment['shortUrl'] ?? payment['short_url']),
      amount: _num(data['amount']),
      confirmed: DepositStatus.parse(_str(data['status'])) ==
          DepositStatus.verified,
    );
  }

  /// Ask the backend whether the online hand-over has been paid. Returns the
  /// updated deposit (VERIFIED once the gateway confirms). Throws
  /// `CASH_ONLINE_FAILED` if the link was cancelled/expired.
  Future<CashDeposit> confirmOnline(String depositId) async {
    final res = await _api.post('/agent/cash/online/$depositId/confirm');
    return CashDeposit.fromJson(_unwrap(res.data));
  }

  /// Back out of an unpaid online hand-over: the payment link is cancelled and
  /// the reserved cash returns to the in-hand figure immediately.
  Future<void> cancelOnline(String depositId) async {
    await _api.post('/agent/cash/online/$depositId/cancel');
  }

  Map<String, dynamic> _unwrap(dynamic raw) {
    final data = raw is Map && raw['data'] != null ? raw['data'] : raw;
    // A non-map body means an empty/!2xx response Api.ensureOk already turned
    // into an ApiException upstream, so an empty map here is safe.
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}

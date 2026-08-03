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

/// Which queue a finished task came from.
enum HistoryKind {
  delivery('delivery', 'Deliveries'),
  collection('collection', 'Collections'),
  verification('verification', 'Verifications');

  const HistoryKind(this.code, this.label);
  final String code;
  final String label;

  static HistoryKind parse(String? v) => HistoryKind.values.firstWhere(
        (k) => k.code == v,
        orElse: () => HistoryKind.delivery,
      );
}

/// How a task ended. The backend buckets each module's own status vocabulary
/// into these three so the app doesn't have to know every status string.
enum HistoryOutcome {
  success('success', 'Completed'),
  partial('partial', 'Partial'),
  failed('failed', 'Not completed');

  const HistoryOutcome(this.code, this.label);
  final String code;
  final String label;

  static HistoryOutcome parse(String? v) => HistoryOutcome.values.firstWhere(
        (o) => o.code == v,
        orElse: () => HistoryOutcome.failed,
      );
}

/// One finished task.
class HistoryEntry extends Equatable {
  const HistoryEntry({
    required this.id,
    required this.kind,
    required this.reference,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.outcome,
    this.customerName = '',
    this.amount,
    this.amountDue,
    this.failureReason = '',
    this.recommendation = '',
    this.closedAt,
  });

  final String id;
  final HistoryKind kind;
  final String reference;
  final String title;
  final String subtitle;
  final String status;
  final HistoryOutcome outcome;
  final String customerName;
  final num? amount;
  final num? amountDue;
  final String failureReason;
  final String recommendation;
  final DateTime? closedAt;

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: _str(j['id']),
        kind: HistoryKind.parse(_str(j['type'])),
        reference: _str(j['reference']),
        title: _str(j['title']),
        subtitle: _str(j['subtitle']),
        status: _str(j['status']),
        outcome: HistoryOutcome.parse(_str(j['outcome'])),
        customerName: _str(j['customerName'] ?? j['customer_name']),
        amount: j['amount'] == null ? null : _num(j['amount']),
        amountDue: j['amountDue'] == null ? null : _num(j['amountDue']),
        failureReason: _str(j['failureReason'] ?? j['failure_reason']),
        recommendation: _str(j['recommendation']),
        closedAt: _date(j['closedAt'] ?? j['closed_at']),
      );

  @override
  List<Object?> get props => [id, kind, status, outcome, closedAt];
}

/// One page of history, plus the totals which describe the WHOLE filtered set
/// (not just this page) — so they don't shrink as the agent scrolls.
class HistoryPage extends Equatable {
  const HistoryPage({
    required this.items,
    required this.counts,
    required this.total,
    required this.collectedTotal,
    required this.hasMore,
    required this.offset,
  });

  final List<HistoryEntry> items;
  final Map<String, int> counts;
  final int total;
  final num collectedTotal;
  final bool hasMore;
  final int offset;

  @override
  List<Object?> get props => [items, total, collectedTotal, hasMore, offset];
}

/// Task-history API (`/agents/history`).
///
/// The three task queues exclude finished work, so a completed task used to
/// disappear from the agent's phone entirely. This is the record of it.
class HistoryApi {
  HistoryApi(this._api);

  final Api _api;

  static const pageSize = 20;

  Future<HistoryPage> fetch({
    HistoryKind? kind,
    DateTime? from,
    DateTime? to,
    int offset = 0,
    int limit = pageSize,
  }) async {
    final q = <String, String>{
      'type': kind?.code ?? 'all',
      'limit': '$limit',
      'offset': '$offset',
      if (from != null) 'from': _day(from),
      if (to != null) 'to': _day(to),
    };
    final query = q.entries.map((e) => '${e.key}=${e.value}').join('&');
    // Api.get takes a path-only string, so the query rides in the path.
    final res = await _api.get('/agents/history?$query');
    final data = _unwrap(res.data);
    return HistoryPage(
      items: [
        for (final e in (data['items'] as List? ?? const []))
          HistoryEntry.fromJson(Map<String, dynamic>.from(e as Map)),
      ],
      counts: {
        for (final e in (data['counts'] as Map? ?? const {}).entries)
          e.key.toString(): (_num(e.value)).toInt(),
      },
      total: _num(data['total']).toInt(),
      collectedTotal: _num(data['collectedTotal'] ?? data['collected_total']),
      hasMore: data['hasMore'] == true || data['has_more'] == true,
      offset: offset,
    );
  }

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Map<String, dynamic> _unwrap(dynamic raw) {
    final data = raw is Map && raw['data'] != null ? raw['data'] : raw;
    // A non-map body means an empty/!2xx response Api.ensureOk already turned
    // into an ApiException upstream, so an empty map here is safe.
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }
}

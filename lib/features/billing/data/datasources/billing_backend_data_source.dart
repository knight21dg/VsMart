import 'package:dio/dio.dart';

import '../../../../app/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/billing_cycle.dart';
import '../../domain/entities/billing_enums.dart';
import '../../domain/entities/collection_record.dart';
import '../../domain/entities/credit_ledger_entry.dart';
import '../../domain/entities/invoice.dart';
import '../../domain/entities/repayment.dart';
import '../../domain/entities/statement.dart';
import 'billing_data_source.dart';

/// [BillingDataSource] backed by the backend: credit ledger/statements
/// (`/credit/*`), order invoices (`/billing/invoices`), repayment history
/// (`/payments/history`) and field collections (`/collections/history`).
class BillingBackendDataSource implements BillingDataSource {
  BillingBackendDataSource(this._client);

  final ApiClient _client;

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  List<Map<String, dynamic>> _list(dynamic raw) {
    final data = raw is Map ? raw['data'] : raw;
    final list = data is List ? data : const [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  num _num(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
  DateTime _date(dynamic v) =>
      DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.now();

  @override
  Future<num> getCreditLimit() async {
    final res = await _client.get<dynamic>(ApiConstants.creditDashboard);
    return _num(_obj(res.data)['creditLimit']);
  }

  @override
  Future<List<CreditLedgerEntry>> getLedger() async {
    final res = await _client.get<dynamic>(ApiConstants.creditLedger);
    return _list(res.data).map((j) {
      final type = _txnType(j['type']?.toString());
      return CreditLedgerEntry(
        id: (j['id'] ?? '').toString(),
        type: type,
        status: TransactionStatus.completed,
        amount: _num(j['amount']).abs(),
        date: _date(j['createdAt']),
        description: (j['note'] as String?)?.isNotEmpty == true
            ? j['note'] as String
            : type.label,
        balanceAfter: j['balanceAfter'] == null ? null : _num(j['balanceAfter']),
      );
    }).toList();
  }

  @override
  Future<List<Statement>> getStatements() async {
    final res = await _client.get<dynamic>(ApiConstants.creditStatements);
    return _list(res.data).map((j) {
      final due = _num(j['closingBalance']);
      return Statement(
        statementId: (j['id'] ?? '').toString(),
        cycleId: (j['id'] ?? '').toString(),
        generatedDate: _date(j['periodEnd']),
        transactions: const [],
        amountDue: due,
        minimumDue: (due * 0.1).ceilToDouble(),
        dueDate: _date(j['dueDate']),
        paid: (j['status']?.toString() ?? '') == 'paid',
      );
    }).toList();
  }

  @override
  Future<List<BillingCycle>> getCycles() async {
    final res = await _client.get<dynamic>(ApiConstants.creditStatements);
    return _list(res.data)
        .map((j) => BillingCycle(
              cycleId: (j['id'] ?? '').toString(),
              startDate: _date(j['periodStart']),
              endDate: _date(j['periodEnd']),
              dueDate: _date(j['dueDate']),
              openingBalance: _num(j['openingBalance']),
              newPurchases: _num(j['purchases']),
              paymentsReceived: _num(j['payments']),
              penalties: _num(j['fees']),
              closingBalance: _num(j['closingBalance']),
            ))
        .toList();
  }

  @override
  Future<List<Invoice>> getInvoices() async {
    final res = await _client.get<dynamic>(ApiConstants.billingInvoices);
    return _list(res.data)
        .map((j) => Invoice(
              invoiceId: (j['number'] ?? j['id'] ?? '').toString(),
              orderId: (j['orderId'] ?? '').toString(),
              amount: _num(j['amount']),
              generatedDate: _date(j['issuedAt']),
              status: _invoiceStatus(j['status']?.toString()),
            ))
        .toList();
  }

  @override
  Future<List<Repayment>> getPaymentHistory() async {
    final res = await _client.get<dynamic>(ApiConstants.paymentHistory);
    return _list(res.data)
        .where((j) => (j['purpose']?.toString() ?? '') == 'repayment')
        .map((j) => Repayment(
              id: (j['id'] ?? '').toString(),
              amount: _num(j['amount']),
              method: _repayMethod(j['method']?.toString()),
              status: _payStatus(j['status']?.toString()),
              date: _date(j['createdAt']),
              reference: j['gatewayOrderId'] as String?,
            ))
        .toList();
  }

  @override
  Future<List<CollectionRecord>> getCollections() async {
    final res = await _client.get<dynamic>(ApiConstants.collectionsHistory);
    return _list(res.data)
        .map((j) => CollectionRecord(
              id: (j['id'] ?? '').toString(),
              amount: _num(j['amount']),
              status: _collectionStatus(j['status']?.toString()),
              createdAt: _date(j['createdAt']),
              collectedAt: j['collectedAt'] == null ? null : _date(j['collectedAt']),
            ))
        .toList();
  }

  @override
  Future<Repayment> makeRepayment({
    required num amount,
    required RepaymentMethod method,
    String? statementId,
  }) async {
    final res = await _client.post<dynamic>(
      ApiConstants.creditRepay,
      data: {
        'amount': amount,
        'method': _repayMethodToApi(method),
        if (statementId != null && statementId.isNotEmpty)
          'statement_id': statementId,
      },
      options: Options(
        headers: {
          'Idempotency-Key': 'repay_${DateTime.now().microsecondsSinceEpoch}',
        },
      ),
    );
    final j = _obj(res.data);
    final paid = _num(j['amount']);
    return Repayment(
      id: (j['id'] ?? '').toString(),
      amount: paid == 0 ? amount : paid,
      method: method,
      status: _payStatus(j['status']?.toString()),
      date: _date(j['createdAt']),
      reference: j['gatewayOrderId'] as String?,
      statementId: statementId,
    );
  }

  @override
  Future<CollectionRecord> requestCollection({required num amount}) async {
    final res = await _client.post<dynamic>(
      ApiConstants.creditCashCollection,
      data: {'amount': amount},
    );
    final j = _obj(res.data);
    final amt = _num(j['amount']);
    return CollectionRecord(
      id: (j['id'] ?? '').toString(),
      amount: amt == 0 ? amount : amt,
      status: _collectionStatus(j['status']?.toString()),
      createdAt: _date(j['createdAt']),
      collectedAt: j['collectedAt'] == null ? null : _date(j['collectedAt']),
    );
  }

  String _repayMethodToApi(RepaymentMethod m) => switch (m) {
        RepaymentMethod.card => 'card',
        RepaymentMethod.bankTransfer => 'netbanking',
        _ => 'upi',
      };

  // ── enum mapping ──
  TransactionType _txnType(String? t) => switch (t) {
        'repayment' => TransactionType.repayment,
        'refund' => TransactionType.refund,
        'fee' => TransactionType.penalty,
        'adjustment' => TransactionType.adjustment,
        _ => TransactionType.purchase,
      };

  TransactionStatus _payStatus(String? s) => switch (s) {
        'success' => TransactionStatus.completed,
        'failed' => TransactionStatus.failed,
        'refunded' => TransactionStatus.reversed,
        _ => TransactionStatus.pending,
      };

  InvoiceStatus _invoiceStatus(String? s) => switch (s) {
        'paid' => InvoiceStatus.paid,
        'overdue' => InvoiceStatus.overdue,
        'cancelled' => InvoiceStatus.cancelled,
        _ => InvoiceStatus.pending,
      };

  RepaymentMethod _repayMethod(String? m) => switch (m) {
        'card' => RepaymentMethod.card,
        'netbanking' => RepaymentMethod.bankTransfer,
        'cash' => RepaymentMethod.cashCollection,
        _ => RepaymentMethod.upi,
      };

  CollectionStatus _collectionStatus(String? s) => switch (s) {
        'collected' => CollectionStatus.collected,
        'assigned' => CollectionStatus.assigned,
        'failed' => CollectionStatus.failed,
        _ => CollectionStatus.pending,
      };
}

import 'package:dio/dio.dart';

import '../../../../app/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/credit_account.dart';
import '../../domain/entities/credit_payment_result.dart';
import '../../domain/entities/credit_transaction.dart';
import 'credit_data_source.dart';

/// [CreditDataSource] backed by the backend credit API: `/credit/dashboard`,
/// `/credit/ledger`, `/credit/repay`.
class CreditBackendDataSource implements CreditDataSource {
  CreditBackendDataSource(this._client);

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
  DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  CreditAccount _toAccount(Map<String, dynamic> j) => CreditAccount(
        creditLimit: _num(j['creditLimit']),
        outstanding: _num(j['outstanding']),
        vsScore: (j['vsScore'] as num?)?.toInt() ?? 0,
        billingCycle: _cycle(j['billingCycle']),
        status: _accountStatus(j['status']),
        dueDate: _date(j['nextDueDate']),
        nextDueAmount: _num(j['nextDueAmount']),
        purchasesThisMonth: _num(j['purchasesThisMonth']),
        paymentsThisMonth: _num(j['paymentsThisMonth']),
        lenderName: (j['lenderName'] as String?),
        loanAccountNumber: (j['loanAccountNumber'] as String?),
        interestRate: j['interestRate'] == null ? null : _num(j['interestRate']),
        sanctionedLimit:
            j['sanctionedLimit'] == null ? null : _num(j['sanctionedLimit']),
      );

  BillingCycle _cycle(dynamic v) =>
      v?.toString().toLowerCase() == 'weekly' ? BillingCycle.weekly : BillingCycle.monthly;

  CreditAccountStatus _accountStatus(dynamic v) => switch (v?.toString().toLowerCase()) {
        'frozen' => CreditAccountStatus.frozen,
        'closed' => CreditAccountStatus.closed,
        _ => CreditAccountStatus.active,
      };

  @override
  Future<CreditAccount> getAccount() async {
    final res = await _client.get<dynamic>(ApiConstants.creditDashboard);
    return _toAccount(_obj(res.data));
  }

  @override
  Future<List<CreditTransaction>> getTransactions() async {
    final res = await _client.get<dynamic>(ApiConstants.creditLedger);
    return _list(res.data).map((j) {
      final type = (j['type'] ?? '').toString();
      final signed = _num(j['amount']);
      final txType = switch (type) {
        'repayment' => CreditTransactionType.payment,
        'refund' => CreditTransactionType.refund,
        'fee' => CreditTransactionType.fee,
        'adjustment' => CreditTransactionType.adjustment,
        _ => CreditTransactionType.purchase,
      };
      // Credit = reduces outstanding: repayment, refund, or a negative adjustment.
      final isCredit = txType == CreditTransactionType.payment ||
          txType == CreditTransactionType.refund ||
          (txType == CreditTransactionType.adjustment && signed < 0);
      return CreditTransaction(
        id: (j['id'] ?? '').toString(),
        type: txType,
        amount: signed.abs(),
        isCredit: isCredit,
        balanceAfter: j['balanceAfter'] == null ? null : _num(j['balanceAfter']),
        date: _date(j['createdAt']) ?? DateTime.now(),
        description: (j['note'] as String?)?.isNotEmpty == true
            ? j['note'] as String
            : _label(type),
      );
    }).toList();
  }

  @override
  Future<CreditPaymentResult> makePayment({
    required num amount,
    required String method,
  }) async {
    final res = await _client.post<dynamic>(
      ApiConstants.creditRepay,
      data: {'amount': amount, 'method': method.toLowerCase()},
      options: Options(
        headers: {'Idempotency-Key': 'repay_${DateTime.now().microsecondsSinceEpoch}'},
      ),
    );
    final payment = _obj(res.data);
    // Re-read the account so the receipt shows the post-payment balance.
    final account = await getAccount();
    return CreditPaymentResult(
      transactionId: (payment['id'] ?? '').toString(),
      amountPaid: amount,
      method: method,
      account: account,
      scorePointsEarned: 0,
    );
  }

  String _label(String type) => switch (type) {
        'repayment' => 'Repayment',
        'refund' => 'Refund',
        'fee' => 'Fee',
        'adjustment' => 'Adjustment',
        _ => 'Purchase',
      };
}

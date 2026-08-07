import '../../credit/domain/entities/credit_account.dart';

/// Validates whether an order can be paid on VS Credit, and surfaces the
/// shortfall when it cannot.
class CreditCheckoutValidator {
  const CreditCheckoutValidator(this.account);

  final CreditAccount? account;

  num availableCredit() => account?.available ?? 0;

  bool canPurchase(num amount) => availableCredit() >= amount;

  /// Amount by which [amount] exceeds available credit (0 when payable).
  num creditShortfall(num amount) {
    final shortfall = amount - availableCredit();
    return shortfall > 0 ? shortfall : 0;
  }
}

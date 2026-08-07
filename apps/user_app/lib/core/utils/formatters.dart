import 'package:intl/intl.dart';

import '../../app/constants/app_constants.dart';

/// Display formatting helpers for currency, dates, and numbers.
abstract final class Formatters {
  Formatters._();

  static final NumberFormat _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: AppConstants.defaultCurrencySymbol,
    decimalDigits: 2,
  );

  static final NumberFormat _currencyCompact = NumberFormat.compactCurrency(
    locale: 'en_IN',
    symbol: AppConstants.defaultCurrencySymbol,
    decimalDigits: 1,
  );

  static final NumberFormat _decimal = NumberFormat.decimalPattern('en_IN');

  /// e.g. ₹1,299.00
  static String currency(num value) => _currency.format(value);

  /// e.g. ₹1.3K
  static String currencyCompact(num value) => _currencyCompact.format(value);

  static String number(num value) => _decimal.format(value);

  /// e.g. 18 Jun 2026
  static String date(DateTime d) => DateFormat('dd MMM yyyy').format(d);

  /// e.g. 18 Jun 2026, 4:30 PM
  static String dateTime(DateTime d) =>
      DateFormat('dd MMM yyyy, hh:mm a').format(d);

  /// e.g. 4:30 PM
  static String time(DateTime d) => DateFormat('hh:mm a').format(d);

  /// Relative time like "2h ago", "Just now".
  static String relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return date(d);
  }

  /// Masks a phone number, e.g. +91 ******3210.
  static String maskPhone(String phone) {
    if (phone.length < 4) return phone;
    final last = phone.substring(phone.length - 4);
    return '${'*' * (phone.length - 4)}$last';
  }

  /// Percentage with no decimals, e.g. 25%.
  static String percent(num value) => '${value.round()}%';
}

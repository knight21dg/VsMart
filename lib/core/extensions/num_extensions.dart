import '../utils/formatters.dart';

/// Numeric formatting/convenience helpers.
extension NumX on num {
  String get asCurrency => Formatters.currency(this);
  String get asCurrencyCompact => Formatters.currencyCompact(this);
  String get asNumber => Formatters.number(this);
  String get asPercent => Formatters.percent(this);

  /// Discount percentage from an original [from] price to `this` selling price.
  int discountPercentFrom(num from) {
    if (from <= 0 || this >= from) return 0;
    return (((from - this) / from) * 100).round();
  }
}

extension DurationX on int {
  Duration get ms => Duration(milliseconds: this);
  Duration get seconds => Duration(seconds: this);
}

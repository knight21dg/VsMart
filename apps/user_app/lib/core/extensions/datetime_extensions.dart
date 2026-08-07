import '../utils/formatters.dart';

/// DateTime formatting/convenience helpers.
extension DateTimeX on DateTime {
  String get asDate => Formatters.date(this);
  String get asDateTime => Formatters.dateTime(this);
  String get asTime => Formatters.time(this);
  String get asRelative => Formatters.relative(this);

  bool get isToday {
    final now = DateTime.now();
    return year == now.year && month == now.month && day == now.day;
  }

  bool get isYesterday {
    final y = DateTime.now().subtract(const Duration(days: 1));
    return year == y.year && month == y.month && day == y.day;
  }

  DateTime get startOfDay => DateTime(year, month, day);
}

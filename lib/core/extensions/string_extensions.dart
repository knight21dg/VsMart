/// String helpers used across VS Mart.
extension StringX on String {
  bool get isBlank => trim().isEmpty;
  bool get isNotBlank => trim().isNotEmpty;

  /// "hello world" -> "Hello world"
  String get capitalized =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';

  /// "hello world" -> "Hello World"
  String get titleCase => split(' ')
      .map((w) => w.isEmpty ? w : w.capitalized)
      .join(' ');

  /// Initials, e.g. "Vijay Sharma" -> "VS".
  String get initials {
    final parts = trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty);
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String truncate(int max, {String ellipsis = '…'}) =>
      length <= max ? this : '${substring(0, max)}$ellipsis';

  /// Reduces a stored phone (which may be E.164 like "+919100000001") to the
  /// local 10-digit national number used by the address phone field. Falls back
  /// to the trimmed digits if it isn't a 12-digit "91…" number.
  String get localPhone {
    final digits = replaceAll(RegExp(r'\D'), '');
    if (digits.length > 10) return digits.substring(digits.length - 10);
    return digits;
  }
}

extension NullableStringX on String? {
  bool get isNullOrBlank => this == null || this!.trim().isEmpty;
  String orEmpty() => this ?? '';
}

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
}

extension NullableStringX on String? {
  bool get isNullOrBlank => this == null || this!.trim().isEmpty;
  String orEmpty() => this ?? '';
}

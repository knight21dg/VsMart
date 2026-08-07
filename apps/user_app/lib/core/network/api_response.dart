/// Envelope describing the standard VS Mart API response shape:
/// `{ "success": bool, "message": string, "data": <T>, "meta": {...} }`.
///
/// Kept as a hand-written generic (rather than Freezed) because Freezed cannot
/// synthesize `fromJson` for an arbitrary generic [T] without a converter.
class ApiResponse<T> {
  const ApiResponse({
    required this.success,
    this.message,
    this.data,
    this.meta,
  });

  final bool success;
  final String? message;
  final T? data;
  final Map<String, dynamic>? meta;

  /// Parse a JSON map, converting the `data` field with [fromData].
  factory ApiResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? data) fromData,
  ) {
    return ApiResponse<T>(
      success: json['success'] as bool? ?? true,
      message: json['message'] as String?,
      data: json['data'] == null ? null : fromData(json['data']),
      meta: json['meta'] as Map<String, dynamic>?,
    );
  }
}

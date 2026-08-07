/// A stored CIBIL / credit-bureau pull for the current customer.
///
/// [status] distinguishes a real score from a "no record" answer (the number was
/// queried recently, or the bureau has no history yet). [pan] is the full PAN as
/// returned by the bureau.
enum CibilStatus { success, noRecord }

class CibilReport {
  const CibilReport({
    required this.status,
    required this.score,
    required this.band,
    required this.nameOnBureau,
    required this.pan,
    required this.mobile,
    required this.provider,
    required this.source,
    required this.checkedAt,
  });

  final CibilStatus status;
  final int score;
  final String band;
  final String nameOnBureau;
  final String pan;
  final String mobile;
  final String provider;
  final String source;
  final DateTime? checkedAt;

  /// CIBIL scores run 300–900.
  static const int min = 300;
  static const int max = 900;

  bool get hasScore => status == CibilStatus.success && score > 0;

  /// 0..1 position of [score] on the 300–900 gauge.
  double get gaugeFraction =>
      ((score - min) / (max - min)).clamp(0.0, 1.0).toDouble();

  factory CibilReport.fromJson(Map<String, dynamic> json) {
    int asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    return CibilReport(
      status: '${json['status']}' == 'success'
          ? CibilStatus.success
          : CibilStatus.noRecord,
      score: asInt(json['score']),
      band: '${json['band'] ?? ''}',
      nameOnBureau: '${json['nameOnBureau'] ?? ''}',
      pan: '${json['pan'] ?? ''}',
      mobile: '${json['mobile'] ?? ''}',
      provider: '${json['provider'] ?? ''}',
      source: '${json['source'] ?? ''}',
      checkedAt: json['checkedAt'] == null
          ? null
          : DateTime.tryParse('${json['checkedAt']}')?.toLocal(),
    );
  }
}

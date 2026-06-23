import 'package:equatable/equatable.dart';

/// Client bootstrap status from the backend `GET /app-config` (public). Drives
/// the force-update / maintenance gates and exposes runtime feature flags.
class AppStatus extends Equatable {
  const AppStatus({
    required this.minAppVersion,
    required this.maintenance,
    this.maintenanceMessage = "We'll be back shortly.",
    this.featureFlags = const {},
    this.supportPhone,
    this.supportEmail,
  });

  final String minAppVersion;
  final bool maintenance;
  final String maintenanceMessage;
  final Map<String, bool> featureFlags;
  final String? supportPhone;
  final String? supportEmail;

  bool flag(String key, {bool fallback = false}) =>
      featureFlags[key] ?? fallback;

  /// A safe default used when bootstrap can't be reached — fail OPEN so a flaky
  /// config call never bricks the app (per-screen offline handling takes over).
  static const open = AppStatus(minAppVersion: '0.0.0', maintenance: false);

  @override
  List<Object?> get props =>
      [minAppVersion, maintenance, maintenanceMessage, featureFlags];
}

/// `true` when [current] is strictly older than [minimum] (semver-ish, numeric
/// dot segments; missing segments treated as 0).
bool isUpdateRequired(String current, String minimum) {
  int cmp(String a, String b) {
    final pa = a.split('.');
    final pb = b.split('.');
    for (var i = 0; i < (pa.length > pb.length ? pa.length : pb.length); i++) {
      final x = i < pa.length ? int.tryParse(pa[i]) ?? 0 : 0;
      final y = i < pb.length ? int.tryParse(pb[i]) ?? 0 : 0;
      if (x != y) return x - y;
    }
    return 0;
  }

  return cmp(current, minimum) < 0;
}

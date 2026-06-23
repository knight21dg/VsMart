import 'package:equatable/equatable.dart';

/// A reverse-geocoded location resolved from the device's GPS coordinates.
///
/// Produced either by the backend `/geo/reverse` endpoint or, when that returns
/// no usable area, by the device's native reverse geocoding. Cached in a
/// Riverpod provider so the resolved delivery area persists across the session.
class ResolvedLocation extends Equatable {
  const ResolvedLocation({
    required this.latitude,
    required this.longitude,
    this.area = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.formatted = '',
    this.source = '',
  });

  final double latitude;
  final double longitude;

  /// Locality / neighbourhood, e.g. "Banjara Hills". The primary label shown in
  /// the delivery header.
  final String area;
  final String city;
  final String state;
  final String pincode;

  /// Single-line human-readable address.
  final String formatted;

  /// Resolution source: "google" (backend), "native" (device geocoder), or one
  /// of the backend's empty states ("no_key"/"no_result"/"error"/"none").
  final String source;

  bool get hasArea => area.trim().isNotEmpty;

  /// The best short label to surface in the delivery header.
  String get displayLabel {
    if (area.trim().isNotEmpty) return area.trim();
    if (city.trim().isNotEmpty) return city.trim();
    if (formatted.trim().isNotEmpty) return formatted.trim();
    return 'Current location';
  }

  ResolvedLocation copyWith({
    double? latitude,
    double? longitude,
    String? area,
    String? city,
    String? state,
    String? pincode,
    String? formatted,
    String? source,
  }) {
    return ResolvedLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      area: area ?? this.area,
      city: city ?? this.city,
      state: state ?? this.state,
      pincode: pincode ?? this.pincode,
      formatted: formatted ?? this.formatted,
      source: source ?? this.source,
    );
  }

  @override
  List<Object?> get props =>
      [latitude, longitude, area, city, state, pincode, formatted, source];
}

import 'package:equatable/equatable.dart';

/// A Google Places autocomplete prediction surfaced in the location search list.
class PlaceSuggestion extends Equatable {
  const PlaceSuggestion({
    required this.placeId,
    required this.primary,
    this.secondary = '',
  });

  final String placeId;

  /// Main line, e.g. "Koramangala". Falls back to the full description.
  final String primary;

  /// Supporting line, e.g. "Bengaluru, Karnataka, India".
  final String secondary;

  @override
  List<Object?> get props => [placeId, primary, secondary];
}

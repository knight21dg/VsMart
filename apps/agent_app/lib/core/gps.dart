import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Ask the agent to enable location when a GPS-dependent action (delivery arrive
/// geofence, verification GPS evidence) can't get a device fix. Returns true if
/// they chose to open settings. The flow still continues on its own fallback —
/// this just makes a silent GPS failure visible and actionable.
Future<bool> promptEnableLocation(BuildContext context) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Turn on location'),
      content: const Text(
        'This step needs your GPS location. Please enable location services and '
        'grant permission, then try again.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Open settings'),
        ),
      ],
    ),
  );
  if (open == true) {
    await Geolocator.openLocationSettings();
    return true;
  }
  return false;
}

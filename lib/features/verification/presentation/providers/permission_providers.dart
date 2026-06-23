import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Requests camera access and exposes whether it is granted. Watching this
/// provider triggers the OS permission prompt on first read.
final cameraPermissionProvider = FutureProvider<PermissionStatus>((ref) async {
  return Permission.camera.request();
});

/// Requests photo-library / gallery access.
final galleryPermissionProvider = FutureProvider<PermissionStatus>((ref) async {
  return Permission.photos.request();
});

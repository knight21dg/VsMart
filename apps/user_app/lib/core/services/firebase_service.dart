import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../utils/app_logger.dart';
import 'notification_service.dart';

/// Initializes Firebase. Designed to fail soft: if Firebase isn't configured
/// yet (no `firebase_options.dart` / google-services file), the app still runs.
abstract final class FirebaseService {
  FirebaseService._();

  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  /// Attempts Firebase initialization. Pass [options] from generated
  /// `firebase_options.dart` once the project is connected via FlutterFire.
  static Future<void> init({FirebaseOptions? options}) async {
    try {
      await Firebase.initializeApp(options: options);
      FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler,
      );
      _initialized = true;
      AppLogger.i('Firebase initialized');
    } catch (e, st) {
      _initialized = false;
      AppLogger.w('Firebase not initialized (skipping): $e');
      AppLogger.d(st);
    }
  }
}

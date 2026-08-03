import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_service.dart';

/// Initializes Firebase for the agent app. Designed to fail soft: if Firebase
/// isn't configured yet (no `google-services.json` / `firebase_options.dart`),
/// the app still runs and push simply stays off. Once ops drops the config in,
/// this succeeds and [PushController] wires up on the next authenticated launch.
abstract final class FirebaseService {
  FirebaseService._();

  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  /// Attempts Firebase initialization. Pass [options] from a generated
  /// `firebase_options.dart` once the project is connected via FlutterFire;
  /// on Android the google-services Gradle plugin can supply them instead.
  static Future<void> init({FirebaseOptions? options}) async {
    try {
      await Firebase.initializeApp(options: options);
      FirebaseMessaging.onBackgroundMessage(
        firebaseMessagingBackgroundHandler,
      );
      _initialized = true;
    } catch (e) {
      _initialized = false;
      if (kDebugMode) debugPrint('Firebase not initialized (skipping): $e');
    }
  }
}

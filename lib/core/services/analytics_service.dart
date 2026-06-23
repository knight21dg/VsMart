import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';

import '../utils/app_logger.dart';

/// Funnels product analytics to Firebase Analytics, falling back to the local
/// logger when Firebase is unavailable (e.g. not configured on this build).
///
/// All methods are fire-and-forget (`void`) and never throw, so analytics can
/// never break — or block — a user flow.
class AnalyticsService {
  const AnalyticsService();

  FirebaseAnalytics? get _analytics {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseAnalytics.instance;
    } catch (_) {
      return null;
    }
  }

  void _log(String name, [Map<String, Object>? params]) {
    unawaited(_send(name, params));
  }

  Future<void> _send(String name, Map<String, Object>? params) async {
    try {
      final analytics = _analytics;
      if (analytics != null) {
        await analytics.logEvent(name: name, parameters: params);
        return;
      }
    } catch (_) {
      // fall through to the logger
    }
    AppLogger.i('analytics: $name${params == null ? '' : ' $params'}');
  }

  /// Generic escape hatch for events without a dedicated method.
  void track(String name, [Map<String, Object>? params]) => _log(name, params);

  // ----- Authentication -----
  void appOpen() => _log('app_open');
  void loginStarted() => _log('login_started');
  void otpSent() => _log('otp_sent');
  void otpVerified() => _log('otp_verified');
  void registrationCompleted() => _log('registration_completed');

  // ----- Verification -----
  void addressCompleted() => _log('address_completed');
  void aadhaarUploaded() => _log('aadhaar_uploaded');
  void panUploaded() => _log('pan_uploaded');
  void selfieCaptured() => _log('selfie_captured');
  void creditApplicationStarted() => _log('credit_application_started');
  void creditApplicationCompleted() => _log('credit_application_completed');
  void kycCompleted() => _log('kyc_completed');
  void applicationSubmitted() => _log('verification_submitted');
  void applicationApproved() => _log('verification_approved');
  void applicationRejected() => _log('verification_rejected');
}

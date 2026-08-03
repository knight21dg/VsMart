import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/services/background_service.dart';
import 'core/services/firebase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fail-soft: a no-op until a google-services.json is present (see
  // core/services/push_controller.dart). Never blocks startup.
  await FirebaseService.init();
  // Registers (doesn't start) the on-duty presence foreground service — see
  // core/services/presence_controller.dart for when it actually runs. Must
  // never block startup: a device where this plugin can't initialize should
  // still get a working app, just without background presence.
  try {
    await initializeBackgroundService();
  } catch (e) {
    if (kDebugMode) debugPrint('Background service init failed: $e');
  }
  runApp(const ProviderScope(child: AgentApp()));
}

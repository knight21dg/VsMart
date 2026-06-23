import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/config/app_config.dart';
import 'core/services/firebase_service.dart';
import 'core/storage/hive_service.dart';
import 'core/utils/app_logger.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Environment configuration (reads --dart-define overrides).
  AppConfig.init(flavor: AppFlavor.dev);

  // 2. Local storage (Hive boxes for user, cart, cache, settings).
  await HiveService.instance.init();

  // 3. Firebase (fail-soft: app still runs if not yet configured).
  await FirebaseService.init();

  // 4. System UI preferences.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  AppLogger.i('VS Mart starting in ${AppConfig.instance.flavor.name} mode');

  // 5. Run inside a Riverpod scope.
  runApp(const ProviderScope(child: VSMartApp()));
}

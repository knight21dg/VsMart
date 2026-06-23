import 'package:logger/logger.dart';

import '../../app/config/app_config.dart';

/// App-wide logger. Silenced in production builds.
abstract final class AppLogger {
  AppLogger._();

  static final Logger _logger = Logger(
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 6,
      lineLength: 90,
      colors: true,
      printEmojis: true,
    ),
    level: _enabled ? Level.debug : Level.off,
  );

  static bool get _enabled {
    try {
      return AppConfig.instance.enableLogging;
    } catch (_) {
      return true; // config not yet initialized
    }
  }

  static void d(Object? message) => _logger.d(message);
  static void i(Object? message) => _logger.i(message);
  static void w(Object? message) => _logger.w(message);
  static void e(Object? message, {Object? error, StackTrace? stackTrace}) =>
      _logger.e(message, error: error, stackTrace: stackTrace);
}

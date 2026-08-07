import 'package:dio/dio.dart';

/// Sends the customer's chosen language on every request.
///
/// Catalog *content* — product names, descriptions, category names — lives in
/// the database, so the ARB/`AppLocalizations` files can't touch it. The server
/// resolves those per-language columns and returns them under the ordinary
/// `name` / `description` keys (see `core/i18n.py` on the backend), but it can
/// only do that if we tell it which language to use.
///
/// The resolver is read per request rather than captured once, so switching
/// language in Settings takes effect immediately — no re-login, no app restart.
class LocaleInterceptor extends Interceptor {
  LocaleInterceptor({required this.languageCode});

  /// Returns the active language code ('en' | 'te' | 'hi').
  final String Function() languageCode;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) {
    final code = languageCode();
    if (code.isNotEmpty) {
      // Region-less tag plus an English fallback: the server picks the first
      // supported language it recognises and degrades to English otherwise.
      options.headers['Accept-Language'] =
          code == 'en' ? 'en' : '$code, en;q=0.8';
    }
    handler.next(options);
  }
}

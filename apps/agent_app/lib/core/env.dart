/// Agent app environment. Points at the same VS Mart backend as the customer
/// app. Override at build time with `--dart-define=API_BASE_URL=...` — e.g.
/// for local dev against a phone on the same LAN:
///   --dart-define=API_BASE_URL=http://PC_LAN_IP:8000/api/v1
///
/// Defaults to PRODUCTION, not localhost — unlike user_app (which has a
/// flavor system that defaults to prod), this app has no such fallback, so a
/// release build that forgot the dart-define used to ship silently pointed
/// at 127.0.0.1 (unreachable from any real device) rather than failing
/// loudly. A forgotten flag during local dev now just talks to prod instead
/// (obvious immediately — no dev master OTP, real data), which is a far
/// safer failure mode than a broken build reaching an agent's phone.
abstract final class Env {
  Env._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.thevsmart.com/api/v1',
  );

  /// Dev master OTP (any phone) — same as the customer app's dev flow.
  static const String appName = 'VS Mart Agent';
}

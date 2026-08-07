import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/config/app_config.dart';
import '../../app/constants/storage_keys.dart';
import 'core_providers.dart';

/// Persisted theme mode (system/light/dark), backed by the Hive settings box.
class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final raw = ref
        .read(hiveServiceProvider)
        .settingsBox
        .get(StorageKeys.themeMode, defaultValue: ThemeMode.system.name);
    return ThemeMode.values.firstWhere(
      (m) => m.name == raw,
      orElse: () => ThemeMode.system,
    );
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await ref
        .read(hiveServiceProvider)
        .settingsBox
        .put(StorageKeys.themeMode, mode.name);
  }

  Future<void> toggle() => set(
        state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
      );
}

final themeModeProvider =
    NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

/// Whether the user has completed onboarding.
class OnboardingController extends Notifier<bool> {
  @override
  bool build() {
    // Dev auth bypass also skips onboarding so the app lands straight on Home.
    if (AppConfig.instance.bypassAuth) return true;
    return ref
        .read(hiveServiceProvider)
        .settingsBox
        .get(StorageKeys.onboardingSeen, defaultValue: false) as bool;
  }

  Future<void> complete() async {
    state = true;
    await ref
        .read(hiveServiceProvider)
        .settingsBox
        .put(StorageKeys.onboardingSeen, true);
  }
}

final onboardingSeenProvider =
    NotifierProvider<OnboardingController, bool>(OnboardingController.new);

/// Whether the user chose to browse the app without signing in ("guest mode").
///
/// A guest can explore the full catalog; login is only required to buy or to
/// reach personal/transactional screens (see `kAuthRequiredLocations`). The flag
/// is persisted so guest browsing survives restarts, and cleared on real login.
class GuestModeController extends Notifier<bool> {
  @override
  bool build() => ref
      .read(hiveServiceProvider)
      .settingsBox
      .get(StorageKeys.guestMode, defaultValue: false) as bool;

  Future<void> _set(bool value) async {
    state = value;
    await ref
        .read(hiveServiceProvider)
        .settingsBox
        .put(StorageKeys.guestMode, value);
  }

  /// Enter guest mode (skip login and browse).
  Future<void> enable() => _set(true);

  /// Leave guest mode (e.g. after a successful sign-in).
  Future<void> disable() => _set(false);
}

final guestModeProvider =
    NotifierProvider<GuestModeController, bool>(GuestModeController.new);

/// Whether push notifications are enabled, persisted in the settings box.
class NotificationsEnabledController extends Notifier<bool> {
  @override
  bool build() => ref
      .read(hiveServiceProvider)
      .settingsBox
      .get(StorageKeys.notificationsEnabled, defaultValue: true) as bool;

  Future<void> set(bool enabled) async {
    state = enabled;
    await ref
        .read(hiveServiceProvider)
        .settingsBox
        .put(StorageKeys.notificationsEnabled, enabled);
  }
}

final notificationsEnabledProvider =
    NotifierProvider<NotificationsEnabledController, bool>(
        NotificationsEnabledController.new);

/// Selected app language code (e.g. `en`, `te`, `hi`), persisted in the settings
/// box so the choice survives restarts.
class LocaleController extends Notifier<String> {
  @override
  String build() => ref
      .read(hiveServiceProvider)
      .settingsBox
      .get(StorageKeys.locale, defaultValue: 'en') as String;

  Future<void> set(String code) async {
    state = code;
    await ref
        .read(hiveServiceProvider)
        .settingsBox
        .put(StorageKeys.locale, code);
  }
}

final localeProvider =
    NotifierProvider<LocaleController, String>(LocaleController.new);

/// Device-local security preferences. The app authenticates via OTP, so these
/// are client-side preferences (biometric app-lock + alert opt-ins) persisted in
/// the settings box — there is no server-side password/session model.
class SecurityPrefs {
  const SecurityPrefs({
    this.biometric = false,
    this.notifyNewLogin = true,
    this.notifyPasswordChange = true,
  });

  final bool biometric;
  final bool notifyNewLogin;
  final bool notifyPasswordChange;

  SecurityPrefs copyWith({
    bool? biometric,
    bool? notifyNewLogin,
    bool? notifyPasswordChange,
  }) =>
      SecurityPrefs(
        biometric: biometric ?? this.biometric,
        notifyNewLogin: notifyNewLogin ?? this.notifyNewLogin,
        notifyPasswordChange: notifyPasswordChange ?? this.notifyPasswordChange,
      );
}

class SecurityPrefsController extends Notifier<SecurityPrefs> {
  static const _biometricKey = 'security_biometric';
  static const _notifyLoginKey = 'security_notify_login';
  static const _notifyPwdKey = 'security_notify_pwd';

  dynamic get _box => ref.read(hiveServiceProvider).settingsBox;

  @override
  SecurityPrefs build() => SecurityPrefs(
        biometric: _box.get(_biometricKey, defaultValue: false) as bool,
        notifyNewLogin: _box.get(_notifyLoginKey, defaultValue: true) as bool,
        notifyPasswordChange:
            _box.get(_notifyPwdKey, defaultValue: true) as bool,
      );

  Future<void> setBiometric(bool v) async {
    state = state.copyWith(biometric: v);
    await _box.put(_biometricKey, v);
  }

  Future<void> setNotifyNewLogin(bool v) async {
    state = state.copyWith(notifyNewLogin: v);
    await _box.put(_notifyLoginKey, v);
  }

  Future<void> setNotifyPasswordChange(bool v) async {
    state = state.copyWith(notifyPasswordChange: v);
    await _box.put(_notifyPwdKey, v);
  }
}

final securityPrefsProvider =
    NotifierProvider<SecurityPrefsController, SecurityPrefs>(
        SecurityPrefsController.new);

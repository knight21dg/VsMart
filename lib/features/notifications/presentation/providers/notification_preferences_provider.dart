import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../../shared/providers/core_providers.dart';

/// The user's notification preferences, mirrored from `/notifications/preferences`.
///
/// `categories` is a free-form per-event toggle map (e.g. `orderConfirmed`,
/// `paymentSuccess`) so the granular notification switches persist server-side
/// without a column per toggle.
class NotificationPreferences {
  const NotificationPreferences({
    required this.push,
    required this.sms,
    required this.whatsapp,
    required this.email,
    required this.reminderEnabled,
    required this.reminderOffsetDays,
    this.reminderTime,
    this.categories = const {},
  });

  final bool push;
  final bool sms;
  final bool whatsapp;
  final bool email;
  final bool reminderEnabled;
  final int reminderOffsetDays;

  /// `HH:MM` (24h), or null when unset.
  final String? reminderTime;
  final Map<String, bool> categories;

  static const empty = NotificationPreferences(
    push: true,
    sms: false,
    whatsapp: true,
    email: false,
    reminderEnabled: true,
    reminderOffsetDays: 3,
  );

  bool category(String key, {bool fallback = true}) =>
      categories[key] ?? fallback;

  NotificationPreferences copyWith({
    bool? push,
    bool? sms,
    bool? whatsapp,
    bool? email,
    bool? reminderEnabled,
    int? reminderOffsetDays,
    String? reminderTime,
    Map<String, bool>? categories,
  }) =>
      NotificationPreferences(
        push: push ?? this.push,
        sms: sms ?? this.sms,
        whatsapp: whatsapp ?? this.whatsapp,
        email: email ?? this.email,
        reminderEnabled: reminderEnabled ?? this.reminderEnabled,
        reminderOffsetDays: reminderOffsetDays ?? this.reminderOffsetDays,
        reminderTime: reminderTime ?? this.reminderTime,
        categories: categories ?? this.categories,
      );
}

class NotificationPreferencesController
    extends AsyncNotifier<NotificationPreferences> {
  ApiClient get _api => ref.read(apiClientProvider);

  @override
  Future<NotificationPreferences> build() => _fetch();

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  NotificationPreferences _parse(Map<String, dynamic> j) {
    final cats = <String, bool>{};
    final raw = j['categories'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is bool) cats[k.toString()] = v;
      });
    }
    final t = j['reminderTime']?.toString();
    return NotificationPreferences(
      push: j['push'] as bool? ?? true,
      sms: j['sms'] as bool? ?? false,
      whatsapp: j['whatsapp'] as bool? ?? true,
      email: j['email'] as bool? ?? false,
      reminderEnabled: j['reminderEnabled'] as bool? ?? true,
      reminderOffsetDays: (j['reminderOffsetDays'] as num?)?.toInt() ?? 3,
      reminderTime: (t == null || t.isEmpty) ? null : t.substring(0, 5),
      categories: cats,
    );
  }

  Future<NotificationPreferences> _fetch() async {
    final res = await _api.get<dynamic>(ApiConstants.notificationPreferences);
    return _parse(_obj(res.data));
  }

  Future<void> _patch(Map<String, dynamic> body) async {
    final res = await _api.patch<dynamic>(
      ApiConstants.notificationPreferences,
      data: body,
    );
    state = AsyncData(_parse(_obj(res.data)));
  }

  /// Toggle a top-level channel field (push/sms/whatsapp/email) — optimistic.
  Future<void> setChannel(String key, bool value) async {
    final cur = state.valueOrNull ?? NotificationPreferences.empty;
    state = AsyncData(switch (key) {
      'push' => cur.copyWith(push: value),
      'sms' => cur.copyWith(sms: value),
      'whatsapp' => cur.copyWith(whatsapp: value),
      'email' => cur.copyWith(email: value),
      _ => cur,
    });
    try {
      await _patch({key: value});
    } catch (_) {
      state = await AsyncValue.guard(_fetch);
    }
  }

  /// Toggle a per-event category — optimistic; sends the full merged map.
  Future<void> setCategory(String key, bool value) async {
    final cur = state.valueOrNull ?? NotificationPreferences.empty;
    final merged = {...cur.categories, key: value};
    state = AsyncData(cur.copyWith(categories: merged));
    try {
      await _patch({'categories': merged});
    } catch (_) {
      state = await AsyncValue.guard(_fetch);
    }
  }

  /// Persist the payment-reminder form in one request.
  Future<bool> saveReminders({
    required bool enabled,
    required int offsetDays,
    required String time,
    required bool whatsapp,
    required bool push,
    required bool sms,
  }) async {
    try {
      await _patch({
        'reminderEnabled': enabled,
        'reminderOffsetDays': offsetDays,
        'reminderTime': time,
        'whatsapp': whatsapp,
        'push': push,
        'sms': sms,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}

final notificationPreferencesProvider = AsyncNotifierProvider<
    NotificationPreferencesController, NotificationPreferences>(
  NotificationPreferencesController.new,
);

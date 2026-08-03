import 'package:equatable/equatable.dart';

import '../../../core/api.dart';

// ── parse helpers (null-safe across String / bool / null) ──
String _str(dynamic v) => v == null ? '' : v.toString();

bool _bool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    return s == 'true' || s == '1' || s == 'yes';
  }
  return false;
}

/// One inbox notification (GET /notifications).
class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.data,
    required this.readAt,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final String readAt;
  final bool isRead;
  final String createdAt;

  factory AppNotification.fromMap(Map<String, dynamic> m) {
    final rawData = m['data'];
    return AppNotification(
      id: _str(m['id']),
      type: _str(m['type']),
      title: _str(m['title']),
      body: _str(m['body']),
      data: rawData is Map ? Map<String, dynamic>.from(rawData) : const {},
      readAt: _str(m['readAt'] ?? m['read_at']),
      isRead: _bool(m['isRead'] ?? m['is_read']) ||
          _str(m['readAt'] ?? m['read_at']).isNotEmpty,
      createdAt: _str(m['createdAt'] ?? m['created_at']),
    );
  }

  @override
  List<Object?> get props =>
      [id, type, title, body, data, readAt, isRead, createdAt];
}

/// Thin repository over [Api] for the notifications inbox endpoints. Non-2xx
/// responses throw an [ApiException] via [Api.ensureOk].
class NotificationsRepo {
  NotificationsRepo(this._api);
  final Api _api;

  /// GET /notifications → list, newest first.
  Future<List<AppNotification>> list() async {
    final res = _api.ensureOk(await _api.get('/notifications'));
    return _api.list(res.data).map(AppNotification.fromMap).toList();
  }

  /// POST /notifications/{id}/read → marks one read.
  Future<void> markRead(String id) async {
    _api.ensureOk(await _api.post('/notifications/$id/read'));
  }

  /// POST /notifications/read-all → marks every notification read.
  Future<void> markAllRead() async {
    _api.ensureOk(await _api.post('/notifications/read-all'));
  }
}

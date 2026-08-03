import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

import '../../../core/api.dart';
import '../../../core/base_repository.dart' show BaseRepository;

/// GET /agents/me
class AgentProfile extends Equatable {
  const AgentProfile({
    required this.id,
    required this.code,
    required this.name,
    required this.phone,
    required this.isAvailable,
    required this.assignedPincodes,
    required this.employmentType,
    this.avatarUrl = '',
  });

  final String id;
  final String code;
  final String name;
  final String phone;
  final bool isAvailable;
  final List<String> assignedPincodes;

  /// Set by the store, not the agent. 'monthly' = salaried — the app hides
  /// per-task/lifetime earnings and defaults the agent to their task list
  /// instead, since their pay isn't driven by what's shown there. Anything
  /// else (in practice 'gig', and the empty string a not-yet-loaded profile
  /// starts as) is treated as the historical per-task behaviour.
  final String employmentType;

  /// Empty until the agent completes the first-login photo capture — the
  /// same field a delivery's OrderTracking.agentPhotoUrl is seeded from, so
  /// the customer sees the same face on their tracking screen.
  final String avatarUrl;

  bool get isMonthlyEmployee => employmentType == 'monthly';
  bool get hasAvatar => avatarUrl.isNotEmpty;

  factory AgentProfile.fromMap(Map<String, dynamic> m) {
    final raw = m['assignedPincodes'] ?? m['assigned_pincodes'];
    final pins = raw is List
        ? raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    return AgentProfile(
      id: _str(m['id']),
      code: _str(m['code']),
      name: _str(m['name']),
      phone: _str(m['phone']),
      isAvailable: _bool(m['isAvailable'] ?? m['is_available']),
      assignedPincodes: pins,
      employmentType: _str(m['employmentType'] ?? m['employment_type']),
      avatarUrl: _str(m['avatarUrl'] ?? m['avatar_url']),
    );
  }

  String get displayName => name.isNotEmpty ? name : (code.isNotEmpty ? code : 'Agent');

  @override
  List<Object?> get props => [
        id, code, name, phone, isAvailable, assignedPincodes, employmentType,
        avatarUrl,
      ];
}

/// One day's completed-work counts, as returned inside GET /agents/performance.
class AgentPerformanceDay extends Equatable {
  const AgentPerformanceDay({
    required this.date,
    required this.deliveries,
    required this.collections,
    required this.verifications,
  });

  final DateTime date;
  final int deliveries;
  final int collections;
  final int verifications;

  int get total => deliveries + collections + verifications;

  factory AgentPerformanceDay.fromMap(Map<String, dynamic> m) {
    return AgentPerformanceDay(
      date: DateTime.tryParse(_str(m['date'])) ?? DateTime.now(),
      deliveries: _int(m['deliveries']),
      collections: _int(m['collections']),
      verifications: _int(m['verifications']),
    );
  }

  @override
  List<Object?> get props => [date, deliveries, collections, verifications];
}

/// GET /agents/performance
class AgentPerformance extends Equatable {
  const AgentPerformance({
    required this.deliveriesCompleted,
    required this.collectionsDone,
    required this.verificationsDone,
    this.daily = const [],
  });

  final int deliveriesCompleted;
  final int collectionsDone;
  final int verificationsDone;

  /// Oldest to newest — the last entry is always today.
  final List<AgentPerformanceDay> daily;

  factory AgentPerformance.fromMap(Map<String, dynamic> m) {
    final rawDaily = m['daily'];
    return AgentPerformance(
      deliveriesCompleted:
          _int(m['deliveriesCompleted'] ?? m['deliveries_completed']),
      collectionsDone: _int(m['collectionsDone'] ?? m['collections_done']),
      verificationsDone:
          _int(m['verificationsDone'] ?? m['verifications_done']),
      daily: rawDaily is List
          ? rawDaily
              .whereType<Map>()
              .map((e) =>
                  AgentPerformanceDay.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : const [],
    );
  }

  @override
  List<Object?> get props =>
      [deliveriesCompleted, collectionsDone, verificationsDone, daily];
}

/// GET /agents/attendance/me, POST /agents/attendance/check-in|check-out
class AgentAttendance extends Equatable {
  const AgentAttendance({
    required this.date,
    required this.checkInAt,
    required this.checkOutAt,
    required this.onDuty,
  });

  final String date;
  final String checkInAt;
  final String checkOutAt;
  final bool onDuty;

  bool get checkedIn => checkInAt.isNotEmpty;
  bool get checkedOut => checkOutAt.isNotEmpty;

  factory AgentAttendance.fromMap(Map<String, dynamic> m) {
    return AgentAttendance(
      date: _str(m['date']),
      checkInAt: _str(m['checkInAt'] ?? m['check_in_at']),
      checkOutAt: _str(m['checkOutAt'] ?? m['check_out_at']),
      onDuty: _bool(m['onDuty'] ?? m['on_duty']),
    );
  }

  @override
  List<Object?> get props => [date, checkInAt, checkOutAt, onDuty];
}

/// One day's attendance row, as returned inside GET /agents/attendance/history.
class AttendanceDay extends Equatable {
  const AttendanceDay({
    required this.date,
    required this.checkInAt,
    required this.checkOutAt,
    required this.onDuty,
    this.hoursWorked,
  });

  final DateTime date;
  final String checkInAt;
  final String checkOutAt;
  final bool onDuty;

  /// Null until both check-in and check-out are recorded for the day.
  final double? hoursWorked;

  bool get checkedIn => checkInAt.isNotEmpty;
  bool get checkedOut => checkOutAt.isNotEmpty;

  factory AttendanceDay.fromMap(Map<String, dynamic> m) {
    final rawHours = m['hoursWorked'] ?? m['hours_worked'];
    return AttendanceDay(
      date: DateTime.tryParse(_str(m['date'])) ?? DateTime.now(),
      checkInAt: _str(m['checkInAt'] ?? m['check_in_at']),
      checkOutAt: _str(m['checkOutAt'] ?? m['check_out_at']),
      onDuty: _bool(m['onDuty'] ?? m['on_duty']),
      hoursWorked: rawHours == null ? null : _double(rawHours),
    );
  }

  @override
  List<Object?> get props =>
      [date, checkInAt, checkOutAt, onDuty, hoursWorked];
}

/// GET /agents/attendance/history?month=YYYY-MM
class AttendanceHistory extends Equatable {
  const AttendanceHistory({required this.month, required this.days});

  /// "YYYY-MM" — the month the backend actually resolved (defaults to the
  /// current month when no `month` query param was sent).
  final String month;
  final List<AttendanceDay> days;

  factory AttendanceHistory.fromMap(Map<String, dynamic> m) {
    final raw = m['days'];
    return AttendanceHistory(
      month: _str(m['month']),
      days: raw is List
          ? raw
              .whereType<Map>()
              .map((e) => AttendanceDay.fromMap(Map<String, dynamic>.from(e)))
              .toList()
          : <AttendanceDay>[],
    );
  }

  @override
  List<Object?> get props => [month, days];
}

/// One incentive row from GET /agents/incentives.
class AgentIncentive extends Equatable {
  const AgentIncentive({
    required this.id,
    required this.amount,
    required this.reason,
    required this.period,
    required this.createdAt,
  });

  final String id;
  final double amount;
  final String reason;
  final String period;
  final String createdAt;

  factory AgentIncentive.fromMap(Map<String, dynamic> m) {
    return AgentIncentive(
      id: _str(m['id']),
      amount: _double(m['amount']),
      reason: _str(m['reason']),
      period: _str(m['period']),
      createdAt: _str(m['createdAt'] ?? m['created_at']),
    );
  }

  @override
  List<Object?> get props => [id, amount, reason, period, createdAt];
}

/// GET /agents/earnings
class AgentEarnings extends Equatable {
  const AgentEarnings({
    required this.base,
    required this.incentives,
    required this.total,
  });

  final double base;
  final double incentives;
  final double total;

  factory AgentEarnings.fromMap(Map<String, dynamic> m) {
    return AgentEarnings(
      base: _double(m['base']),
      incentives: _double(m['incentives']),
      total: _double(m['total']),
    );
  }

  @override
  List<Object?> get props => [base, incentives, total];
}

/// Thin repository over [Api] for the dashboard endpoints.
class DashboardRepo extends BaseRepository {
  DashboardRepo(super._api);

  Future<AgentProfile> me() async {
    final res = ensureOk(await get('/agents/me'));
    return AgentProfile.fromMap(obj(res.data));
  }

  /// POST /users/me/avatar (multipart) — the same generic avatar endpoint
  /// every account type uses; ingested through the media engine (EXIF
  /// stripped, re-encoded to WebP) and served publicly, since the customer
  /// app renders it unauthenticated on the order-tracking screen.
  Future<String> uploadAvatar({
    required List<int> bytes,
    required String filename,
  }) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = ensureOk(await postMultipart('/users/me/avatar', form));
    return _str(obj(res.data)['avatarUrl'] ?? obj(res.data)['avatar_url']);
  }

  /// PUT /agents/me {isAvailable} → updated profile (on/off duty toggle).
  Future<AgentProfile> setAvailable(bool isAvailable) async {
    final res = ensureOk(
        await put('/agents/me', data: {'isAvailable': isAvailable}));
    return AgentProfile.fromMap(obj(res.data));
  }

  Future<AgentPerformance> performance() async {
    final res = ensureOk(await get('/agents/performance'));
    return AgentPerformance.fromMap(obj(res.data));
  }

  Future<AgentEarnings> earnings() async {
    final res = ensureOk(await get('/agents/earnings'));
    return AgentEarnings.fromMap(obj(res.data));
  }

  /// GET /agents/attendance/me → today's attendance record.
  Future<AgentAttendance> attendance() async {
    final res = ensureOk(await get('/agents/attendance/me'));
    return AgentAttendance.fromMap(obj(res.data));
  }

  /// POST /agents/attendance/check-in → attendance obj.
  Future<AgentAttendance> checkIn() async {
    final res = ensureOk(await post('/agents/attendance/check-in'));
    return AgentAttendance.fromMap(obj(res.data));
  }

  /// POST /agents/attendance/check-out → attendance obj.
  Future<AgentAttendance> checkOut() async {
    final res = ensureOk(await post('/agents/attendance/check-out'));
    return AgentAttendance.fromMap(obj(res.data));
  }

  /// GET /agents/attendance/history — one calendar month of this agent's
  /// attendance. [month] is "YYYY-MM"; omit for the current month.
  Future<AttendanceHistory> attendanceHistory({String? month}) async {
    final path = month == null
        ? '/agents/attendance/history'
        : '/agents/attendance/history?month=$month';
    final res = ensureOk(await get(path));
    return AttendanceHistory.fromMap(obj(res.data));
  }

  /// GET /agents/incentives → recent incentive rows.
  Future<List<AgentIncentive>> incentives() async {
    final res = ensureOk(await get('/agents/incentives'));
    return list(res.data).map(AgentIncentive.fromMap).toList();
  }
}


// ── file-local JSON coercion helpers (used by the factories above) ──
num _num(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v) ?? 0;
  return 0;
}

int _int(dynamic v) => _num(v).toInt();

double _double(dynamic v) => _num(v).toDouble();

String _str(dynamic v) => v == null ? '' : v.toString();

bool _bool(dynamic v) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final t = v.toLowerCase();
    return t == 'true' || t == '1' || t == 'yes';
  }
  return false;
}

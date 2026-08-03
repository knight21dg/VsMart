import '../../../core/api.dart';

num _num(dynamic v) => v is num ? v : (v is String ? (num.tryParse(v) ?? 0) : 0);
int _int(dynamic v) => _num(v).toInt();
double _dbl(dynamic v) => _num(v).toDouble();
double? _dblOrNull(dynamic v) =>
    v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));
String _str(dynamic v) => v == null ? '' : v.toString();

/// One stop on the agent's route — a delivery (order) or a cash collection.
class RouteStop {
  const RouteStop({
    required this.sequence,
    required this.kind,
    required this.label,
    required this.status,
    this.lat,
    this.lng,
    this.amount = 0,
    this.taskId,
    this.orderCode,
    this.collectionId,
    this.phone = '',
    this.address = '',
  });

  final int sequence;
  final String kind; // delivery | collection
  final String label;
  final String status; // pending | reached | done | failed
  final double? lat;
  final double? lng;
  final double amount;
  final String? taskId;
  final String? orderCode;
  final String? collectionId;
  final String phone;
  final String address;

  bool get isDelivery => kind == 'delivery';
  bool get isDone => status == 'done' || status == 'failed';

  factory RouteStop.fromMap(Map<String, dynamic> m) => RouteStop(
        sequence: _int(m['sequence']),
        kind: _str(m['kind']),
        label: _str(m['label']),
        status: _str(m['status']),
        lat: _dblOrNull(m['lat']),
        lng: _dblOrNull(m['lng']),
        amount: _dbl(m['amount']),
        taskId: m['taskId'] == null ? null : _str(m['taskId']),
        orderCode: m['orderCode'] == null ? null : _str(m['orderCode']),
        collectionId: m['collectionId'] == null ? null : _str(m['collectionId']),
        phone: _str(m['phone']),
        address: _str(m['address']),
      );
}

/// The agent's planned trip — an ordered set of stops assigned by the engine.
class RouteBatch {
  const RouteBatch({
    required this.id,
    required this.status,
    required this.priority,
    required this.totalDistanceKm,
    required this.etaMinutes,
    required this.storeName,
    required this.storeAddress,
    this.storeLat,
    this.storeLng,
    required this.doneStops,
    required this.totalStops,
    required this.stops,
  });

  final int id;
  final String status; // assigned | accepted | picked_up | in_progress | completed
  final String priority;
  final double totalDistanceKm;
  final int etaMinutes;
  final String storeName;
  final String storeAddress;
  final double? storeLat;
  final double? storeLng;
  final int doneStops;
  final int totalStops;
  final List<RouteStop> stops;

  bool get needsAccept => status == 'assigned' || status == 'queued';
  bool get needsPickup => status == 'accepted';
  bool get inProgress => status == 'in_progress' || status == 'picked_up';

  factory RouteBatch.fromMap(Map<String, dynamic> m) {
    final store = m['store'] is Map ? Map<String, dynamic>.from(m['store']) : const {};
    final progress = m['progress'] is Map ? Map<String, dynamic>.from(m['progress']) : const {};
    final stops = (m['stops'] as List? ?? const [])
        .whereType<Map>()
        .map((s) => RouteStop.fromMap(Map<String, dynamic>.from(s)))
        .toList();
    return RouteBatch(
      id: _int(m['id']),
      status: _str(m['status']),
      priority: _str(m['priority']),
      totalDistanceKm: _dbl(m['totalDistanceKm']),
      etaMinutes: _int(m['etaMinutes']),
      storeName: _str(store['name']),
      storeAddress: _str(store['address']),
      storeLat: _dblOrNull(store['lat']),
      storeLng: _dblOrNull(store['lng']),
      doneStops: _int(progress['done']),
      totalStops: _int(progress['total']),
      stops: stops,
    );
  }
}

/// Repository over [Api] for the batched guided-route endpoints.
class BatchRepo {
  BatchRepo(this._api);
  final Api _api;

  /// GET /deliveries/batch/current → the active trip, or null if none.
  Future<RouteBatch?> current() async {
    final res = await _api.get('/deliveries/batch/current');
    final raw = res.data;
    final data = raw is Map ? raw['data'] : null;
    if (data is! Map || data['id'] == null) return null;
    return RouteBatch.fromMap(Map<String, dynamic>.from(data));
  }

  Future<RouteBatch> detail(int id) async {
    final res = await _api.get('/deliveries/batch/$id');
    return RouteBatch.fromMap(_api.obj(res.data));
  }

  Future<RouteBatch> accept(int id) async {
    final res = await _api.post('/deliveries/batch/$id/accept');
    return RouteBatch.fromMap(_api.obj(res.data));
  }

  /// Confirm the store handoff with the pickup code shown on the dispatch board.
  Future<RouteBatch> pickup(int id, String code) async {
    final res = await _api.post('/deliveries/batch/$id/pickup', data: {'code': code});
    return RouteBatch.fromMap(_api.obj(res.data));
  }

  /// Reject (pre-pickup) or report a mid-route issue — unfinished stops go back to
  /// the queue and are reassigned to other agents.
  Future<void> abandon(int id, String reason) async {
    await _api.post('/deliveries/batch/$id/abandon', data: {'reason': reason});
  }
}

import 'package:equatable/equatable.dart';

import '../../../app/constants/api_constants.dart';
import '../../../core/network/api_client.dart';

/// A recurring product subscription, from `GET /subscriptions`.
class Subscription extends Equatable {
  const Subscription({
    required this.id,
    required this.quantity,
    required this.frequency,
    required this.status,
    required this.productId,
    required this.productName,
    required this.price,
    this.nextDelivery,
    this.createdAt,
    this.imageUrl,
  });

  final String id;
  final int quantity;

  /// One of: `weekly`, `biweekly`, `monthly`.
  final String frequency;

  /// One of: `active`, `paused`, `cancelled`.
  final String status;
  final String productId;
  final String productName;
  final num price;
  final String? nextDelivery;
  final String? createdAt;
  final String? imageUrl;

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isCancelled => status == 'cancelled';

  @override
  List<Object?> get props => [
        id,
        quantity,
        frequency,
        status,
        productId,
        productName,
        price,
        nextDelivery,
        createdAt,
        imageUrl,
      ];
}

/// Backend subscriptions API: `/subscriptions`, `/subscriptions/{id}`.
class SubscriptionRemoteDataSource {
  SubscriptionRemoteDataSource(this._client);

  final ApiClient _client;

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] != null ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  List<dynamic> _listData(dynamic raw) {
    final data = raw is Map && raw['data'] != null ? raw['data'] : raw;
    return data is List ? data : <dynamic>[];
  }

  num _num(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;

  String? _str(dynamic v) => v?.toString();

  Subscription _parse(Map<String, dynamic> j) {
    return Subscription(
      id: (j['id'] ?? '').toString(),
      quantity: (j['quantity'] as num?)?.toInt() ?? 1,
      frequency: (j['frequency'] ?? 'monthly').toString(),
      status: (j['status'] ?? 'active').toString(),
      productId: (j['productId'] ?? '').toString(),
      productName: (j['productName'] ?? '').toString(),
      price: _num(j['price']),
      nextDelivery: _str(j['nextDelivery']),
      createdAt: _str(j['createdAt']),
      imageUrl: _str(j['imageUrl']),
    );
  }

  Future<List<Subscription>> list() async {
    final res = await _client.get<dynamic>(ApiConstants.subscriptions);
    return _listData(res.data)
        .whereType<Map>()
        .map((e) => _parse(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Subscription> create({
    required String productId,
    int quantity = 1,
    required String frequency,
  }) async {
    final res = await _client.post<dynamic>(
      ApiConstants.subscriptions,
      data: {
        'productId': productId,
        'quantity': quantity,
        'frequency': frequency,
      },
    );
    return _parse(_obj(res.data));
  }

  /// PATCH `{action: 'pause' | 'resume' | 'cancel'}`.
  Future<Subscription> updateAction(String id, String action) async {
    final res = await _client.patch<dynamic>(
      ApiConstants.subscription(id),
      data: {'action': action},
    );
    return _parse(_obj(res.data));
  }

  Future<void> cancel(String id) async {
    await _client.delete<dynamic>(ApiConstants.subscription(id));
  }
}

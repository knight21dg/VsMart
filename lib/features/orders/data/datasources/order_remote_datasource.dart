import 'package:dio/dio.dart';

import '../../../../app/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../cart/domain/entities/cart_item.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/order_enums.dart';
import '../../domain/entities/order_parts.dart';
import '../../domain/entities/order_tracking.dart';

/// Backend orders + checkout API. Syncs the local cart to the server cart, places
/// the order via `POST /checkout` (server builds it from the server cart + reserves
/// stock), and reads order history/detail. Maps the backend order JSON → entities.
class OrderRemoteDataSource {
  OrderRemoteDataSource(this._client);

  final ApiClient _client;

  // ── envelope helpers ──
  List<Map<String, dynamic>> _list(dynamic raw) {
    final data = raw is Map ? raw['data'] : raw;
    final list = data is List ? data : const [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Map<String, dynamic> _obj(dynamic raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    return data is Map ? Map<String, dynamic>.from(data) : <String, dynamic>{};
  }

  // ── cart sync (server cart is the source of truth for checkout) ──
  Future<void> _syncCart(List<CartItem> items) async {
    final res = await _client.get<dynamic>(ApiConstants.cart);
    final data = _obj(res.data);
    final existing = (data['items'] as List?) ?? const [];
    for (final it in existing) {
      final id = (it as Map)['id'];
      if (id != null) {
        await _client.delete<dynamic>(ApiConstants.cartItem(id.toString()));
      }
    }
    for (final item in items) {
      await _client.post<dynamic>(
        ApiConstants.cartItems,
        data: {
          'product_id': item.productId,
          'quantity': item.quantity,
          if (item.variantId != null) 'variant_id': item.variantId,
        },
      );
    }
  }

  // ── checkout ──
  Future<Order> checkout({
    required List<CartItem> items,
    required String addressId,
    required PaymentMethod method,
    String? couponCode,
    String deliverySlot = '',
    String? creditPlan,
    required String idempotencyKey,
  }) async {
    await _syncCart(items);
    final res = await _client.post<dynamic>(
      ApiConstants.checkout,
      data: {
        'address_id': addressId,
        'payment_method': _methodToApi(method),
        if (deliverySlot.isNotEmpty) 'delivery_slot': deliverySlot,
        if (couponCode != null && couponCode.isNotEmpty) 'coupon_code': couponCode,
        // Repayment plan only applies to a VS Credit purchase.
        if (method == PaymentMethod.credit &&
            creditPlan != null &&
            creditPlan.isNotEmpty)
          'credit_plan': creditPlan,
      },
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    return _toOrder(_obj(res.data));
  }

  // ── reads ──
  Future<List<Order>> list() async {
    final res = await _client.get<dynamic>(ApiConstants.orders);
    return _list(res.data).map(_toOrder).toList();
  }

  Future<Order> detail(String code) async {
    final res = await _client.get<dynamic>(ApiConstants.orderDetails(code));
    return _toOrder(_obj(res.data));
  }

  Future<Order> cancel(String code) async {
    final res = await _client.post<dynamic>('${ApiConstants.orderDetails(code)}/cancel');
    return _toOrder(_obj(res.data));
  }

  /// Fetches live tracking from `GET /orders/<code>/tracking` (real delivery
  /// agent + ETA when an agent is assigned), falling back to order-derived data.
  /// Only surfaces an agent when the backend actually assigned one — no fakes.
  Future<OrderTracking> tracking(Order order) async {
    final active = order.status.isActive;
    String? agentName;
    String? agentPhone;
    String? etaLabel;
    double? lat;
    double? lng;
    try {
      final res =
          await _client.get<dynamic>(ApiConstants.orderTracking(order.id));
      final j = _obj(res.data);
      final name = (j['agentName'] ?? '').toString();
      if (name.isNotEmpty) agentName = name;
      final phone = (j['agentPhone'] ?? '').toString();
      if (phone.isNotEmpty) agentPhone = phone;
      final eta = (j['eta'] ?? '').toString();
      if (eta.isNotEmpty) etaLabel = eta;
      lat = (j['latitude'] as num?)?.toDouble();
      lng = (j['longitude'] as num?)?.toDouble();
    } catch (_) {/* fall back to order-derived tracking below */}

    return OrderTracking(
      orderId: order.id,
      currentStatus: order.status,
      timeline: order.timeline.isNotEmpty
          ? order.timeline
          : _timeline(order.status, order.placedAt),
      agentName: agentName,
      agentPhone: agentPhone,
      etaLabel: etaLabel ?? (active ? 'Arriving by ${_eta(order)}' : null),
      agentLat: lat,
      agentLng: lng,
      hasLiveLocation: lat != null && lng != null,
    );
  }

  // ── mapping ──
  Order _toOrder(Map<String, dynamic> j) {
    final placedAt = _date(j['placedAt']) ?? DateTime.now();
    final addr = (j['addressSnapshot'] as Map?) ?? const {};
    final items = ((j['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => _toItem(Map<String, dynamic>.from(e)))
        .toList();
    final status = _status(j['status']?.toString());
    final total = _num(j['total']);
    final creditUsed = _num(j['creditUsed']);
    final timelineJson = (j['timeline'] as List?) ?? const [];
    final timeline = timelineJson.isNotEmpty
        ? _timelineFromJson(timelineJson, status, placedAt)
        : _timeline(status, placedAt);
    return Order(
      id: (j['id'] ?? '').toString(),
      items: items,
      address: OrderAddress(
        name: (addr['name'] ?? '').toString(),
        phone: (addr['phone'] ?? '').toString(),
        formatted: (addr['formatted'] ?? '').toString(),
        pincode: (addr['pincode'] ?? '').toString(),
      ),
      payment: OrderPayment(
        method: _methodFromApi(j['paymentMethod']?.toString()),
        status: _payStatus(j['paymentStatus']?.toString()),
        amount: total,
        creditUsed: creditUsed,
      ),
      summary: OrderSummary(
        itemTotal: _num(j['subtotal']),
        deliveryFee: _num(j['deliveryFee']),
        grandTotal: total,
        discount: _num(j['discount']),
        creditUsed: creditUsed,
      ),
      status: status,
      placedAt: placedAt,
      estimatedDelivery: _date(j['estimatedDelivery']),
      timeline: timeline,
    );
  }

  OrderItem _toItem(Map<String, dynamic> j) => OrderItem(
        productId: (j['productId'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        brand: (j['brand'] ?? '').toString(),
        unit: (j['unit'] ?? '').toString(),
        price: _num(j['price']),
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        mrp: j['mrp'] == null ? null : _num(j['mrp']),
        imageUrl: j['imageUrl'] as String?,
      );

  num _num(dynamic v) => v is num ? v : num.tryParse(v?.toString() ?? '') ?? 0;
  DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  OrderStatus _status(String? s) => switch (s) {
        'draft' => OrderStatus.draft,
        'placed' => OrderStatus.placed,
        'pending' => OrderStatus.pending,
        'confirmed' => OrderStatus.confirmed,
        'packed' => OrderStatus.packed,
        'ready_for_dispatch' => OrderStatus.readyForDispatch,
        'out_for_delivery' => OrderStatus.outForDelivery,
        'delivered' => OrderStatus.delivered,
        'cancelled' => OrderStatus.cancelled,
        'rejected' => OrderStatus.rejected,
        'returned' => OrderStatus.returned,
        'partially_returned' => OrderStatus.partiallyReturned,
        'failed_delivery' => OrderStatus.failedDelivery,
        _ => OrderStatus.pending,
      };

  PaymentMethod _methodFromApi(String? m) => switch (m) {
        'credit' => PaymentMethod.credit,
        'upi' => PaymentMethod.upi,
        'card' => PaymentMethod.card,
        _ => PaymentMethod.cashOnDelivery,
      };

  String _methodToApi(PaymentMethod m) => switch (m) {
        PaymentMethod.credit => 'credit',
        PaymentMethod.upi => 'upi',
        PaymentMethod.card => 'card',
        PaymentMethod.cashOnDelivery => 'cod',
      };

  PaymentStatus _payStatus(String? s) => switch (s) {
        'paid' => PaymentStatus.paid,
        'failed' => PaymentStatus.failed,
        'refunded' => PaymentStatus.refunded,
        _ => PaymentStatus.pending,
      };

  static const _flow = [
    OrderStatus.confirmed,
    OrderStatus.packed,
    OrderStatus.readyForDispatch,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
  ];

  List<OrderTimelineEntry> _timeline(OrderStatus status, DateTime placedAt) {
    final idx = _flow.indexOf(status);
    return [
      OrderTimelineEntry(
          status: OrderStatus.pending, label: 'Order Placed', at: placedAt, done: true),
      for (var i = 0; i < _flow.length; i++)
        OrderTimelineEntry(
          status: _flow[i],
          label: _flow[i].label,
          done: idx >= i,
          at: idx >= i ? placedAt.add(Duration(minutes: 15 * (i + 1))) : null,
        ),
    ];
  }

  List<OrderTimelineEntry> _timelineFromJson(
      List<dynamic> events, OrderStatus status, DateTime placedAt) {
    // Backend events are past milestones; fold them into the standard flow.
    final reached = events
        .whereType<Map>()
        .map((e) => _status(e['status']?.toString()))
        .toSet();
    return [
      OrderTimelineEntry(
          status: OrderStatus.pending, label: 'Order Placed', at: placedAt, done: true),
      for (final s in _flow)
        OrderTimelineEntry(
          status: s,
          label: s.label,
          done: reached.contains(s) || status.index >= s.index,
        ),
    ];
  }

  String _eta(Order order) {
    final eta = order.estimatedDelivery;
    if (eta == null) return 'today';
    final h = eta.hour % 12 == 0 ? 12 : eta.hour % 12;
    final ampm = eta.hour >= 12 ? 'PM' : 'AM';
    return '$h:${eta.minute.toString().padLeft(2, '0')} $ampm';
  }
}

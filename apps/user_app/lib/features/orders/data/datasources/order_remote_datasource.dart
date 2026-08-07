import 'package:dio/dio.dart';

import '../../../../app/constants/api_constants.dart';
import '../../../../core/network/api_client.dart';
import '../../../cart/domain/entities/cart_item.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/order_enums.dart';
import '../../domain/entities/order_parts.dart';
import '../../domain/entities/order_feedback.dart';
import '../../domain/entities/order_tracking.dart';
import '../../domain/entities/reorder_line.dart';

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
  /// Makes the server cart exactly [items] in a single atomic `PUT /cart`.
  ///
  /// This used to read the server cart, DELETE every line, then POST each local
  /// item back one at a time. `POST /cart/items` ACCUMULATES, so that sequence was
  /// neither atomic nor safe to replay: a failure partway left a partial cart on
  /// the server, and the retry re-added the lines that had already landed —
  /// doubling their quantity and charging for a basket the customer never built.
  ///
  /// The PUT carries absolute quantities and applies in one transaction, so
  /// retrying converges on the same cart instead of climbing.
  Future<void> _syncCart(List<CartItem> items) async {
    await _client.put<dynamic>(
      ApiConstants.cart,
      data: {
        'items': [
          for (final item in items)
            {
              'product_id': item.productId,
              'quantity': item.quantity,
              if (item.variantId != null) 'variant_id': item.variantId,
            },
        ],
      },
    );
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

  /// What a reorder would add, priced live, with the original pack preserved.
  ///
  /// One request instead of re-fetching every product individually — and the
  /// server is the authority on what's still sold and in stock at this customer's
  /// store, which the client cannot determine on its own.
  Future<ReorderPlan> reorderPreview(String code) async {
    final res =
        await _client.get<dynamic>(ApiConstants.orderReorderPreview(code));
    return ReorderPlan.fromJson(_obj(res.data));
  }

  /// Fetches live tracking from `GET /orders/<code>/tracking` (real delivery
  /// agent + ETA when an agent is assigned), falling back to order-derived data.
  /// Only surfaces an agent when the backend actually assigned one — no fakes.
  Future<OrderTracking> tracking(Order order) async {
    final active = order.status.isActive;
    String? agentName;
    String? agentPhone;
    String? agentPhotoUrl;
    String? etaLabel;
    double? lat;
    double? lng;
    double? storeLat;
    double? storeLng;
    double? destLat;
    double? destLng;
    var otpCode = '';
    try {
      final res =
          await _client.get<dynamic>(ApiConstants.orderTracking(order.id));
      final j = _obj(res.data);
      final name = (j['agentName'] ?? '').toString();
      if (name.isNotEmpty) agentName = name;
      final phone = (j['agentPhone'] ?? '').toString();
      if (phone.isNotEmpty) agentPhone = phone;
      final photo = (j['agentPhotoUrl'] ?? '').toString();
      if (photo.isNotEmpty) agentPhotoUrl = photo;
      final eta = (j['eta'] ?? '').toString();
      if (eta.isNotEmpty) etaLabel = eta;
      lat = (j['latitude'] as num?)?.toDouble();
      lng = (j['longitude'] as num?)?.toDouble();
      storeLat = (j['storeLat'] as num?)?.toDouble();
      storeLng = (j['storeLng'] as num?)?.toDouble();
      destLat = (j['destLat'] as num?)?.toDouble();
      destLng = (j['destLng'] as num?)?.toDouble();
      otpCode = (j['deliveryOtp'] ?? '').toString();
    } catch (_) {/* fall back to order-derived tracking below */}

    return OrderTracking(
      orderId: order.id,
      currentStatus: order.status,
      deliveryOtp: otpCode,
      timeline: order.timeline.isNotEmpty
          ? order.timeline
          : _timeline(order.status, order.placedAt),
      agentName: agentName,
      agentPhone: agentPhone,
      agentPhotoUrl: agentPhotoUrl,
      etaLabel: etaLabel ?? (active ? 'Arriving by ${_eta(order)}' : null),
      agentLat: lat,
      agentLng: lng,
      storeLat: storeLat,
      storeLng: storeLng,
      destLat: destLat,
      destLng: destLng,
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
        amountPaid: _num(j['amountPaid']),
        amountRefunded: _num(j['amountRefunded']),
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

  /// Timeline when the backend sent NO events (legacy orders). Rungs up to the
  /// current status are shown reached, but with NO timestamps: this used to
  /// stamp each one `placedAt + 15/30/45 min` — invented times rendered exactly
  /// like real history, so "Packed 2:45 PM" could name a minute at which nothing
  /// happened. Unknown time is shown as no time, not a plausible lie.
  List<OrderTimelineEntry> _timeline(OrderStatus status, DateTime placedAt) {
    // Position along the DELIVERY FLOW — never the enum ordinal. (The terminal
    // failure states are declared after `delivered`, so an ordinal comparison
    // rendered a cancelled order as fully delivered.)
    final idx = _flow.indexOf(status);
    return [
      OrderTimelineEntry(
          status: OrderStatus.pending, label: 'Order Placed', at: placedAt, done: true),
      for (var i = 0; i < _flow.length; i++)
        OrderTimelineEntry(
          status: _flow[i],
          label: _flow[i].label,
          done: idx >= i,
          at: null,
        ),
    ];
  }

  /// Timeline from the backend's recorded status events — and ONLY from them.
  ///
  /// This used to tick every flow rung at or below the current status
  /// (`idx >= i`), so a store that legitimately jumped confirmed →
  /// ready_for_dispatch produced a ticked "Packed" nobody ever performed — a
  /// customer watching their own order saw a step happen that never did. Now a
  /// rung is shown only if it truly occurred (it has an event, or it IS the
  /// current status), skipped rungs disappear from history, and the steps still
  /// ahead render unticked so the ladder keeps showing where the order goes next.
  List<OrderTimelineEntry> _timelineFromJson(
      List<dynamic> events, OrderStatus status, DateTime placedAt) {
    // Real events, oldest first, first-occurrence timestamp per status.
    final at = <OrderStatus, DateTime>{};
    final order = <OrderStatus>[];
    for (final e in events.whereType<Map>()) {
      final s = _status(e['status']?.toString());
      final when = _date(e['at']);
      if (!at.containsKey(s)) {
        at[s] = when ?? placedAt;
        order.add(s);
      }
    }

    const placedLike = {OrderStatus.draft, OrderStatus.pending, OrderStatus.placed};
    final entries = <OrderTimelineEntry>[
      // The order-created milestone; covers any pending/placed/draft events.
      OrderTimelineEntry(
        status: OrderStatus.pending,
        label: 'Order Placed',
        at: at[OrderStatus.pending] ?? at[OrderStatus.placed] ?? placedAt,
        done: true,
      ),
      for (final s in order)
        if (!placedLike.contains(s))
          OrderTimelineEntry(status: s, label: s.label, at: at[s], done: true),
    ];

    // The current status is authoritative even when its event is missing —
    // shown reached, with no invented time.
    if (!placedLike.contains(status) && !at.containsKey(status)) {
      entries.add(OrderTimelineEntry(
          status: status, label: status.label, at: null, done: true));
    }

    // What's still ahead on the standard flow (nothing for terminal/off-flow
    // statuses like cancelled — those steps genuinely aren't coming).
    final idx = _flow.indexOf(status);
    if (idx != -1) {
      for (var i = idx + 1; i < _flow.length; i++) {
        if (!at.containsKey(_flow[i])) {
          entries.add(OrderTimelineEntry(
              status: _flow[i], label: _flow[i].label, at: null, done: false));
        }
      }
    }
    return entries;
  }

  String _eta(Order order) {
    final eta = order.estimatedDelivery;
    if (eta == null) return 'today';
    final h = eta.hour % 12 == 0 ? 12 : eta.hour % 12;
    final ampm = eta.hour >= 12 ? 'PM' : 'AM';
    return '$h:${eta.minute.toString().padLeft(2, '0')} $ampm';
  }

  /// Current feedback state for an order (is it open, what was said).
  Future<OrderFeedback> getFeedback(String code) async {
    final res = await _client.get<dynamic>(ApiConstants.orderFeedback(code));
    final d = res.data is Map && res.data['data'] is Map
        ? res.data['data']
        : res.data;
    if (d is! Map) return const OrderFeedback.unavailable();
    return OrderFeedback.fromJson(Map<String, dynamic>.from(d));
  }

  /// Submit (or change) the rating for a delivered order.
  Future<OrderFeedback> submitFeedback(
    String code, {
    required int rating,
    String comment = '',
  }) async {
    final res = await _client.post<dynamic>(
      ApiConstants.orderFeedback(code),
      data: {'rating': rating, 'feedback': comment},
    );
    final d = res.data is Map && res.data['data'] is Map
        ? res.data['data']
        : res.data;
    return OrderFeedback.fromJson(Map<String, dynamic>.from(d as Map));
  }

}

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:user_app/core/network/api_client.dart';
import 'package:user_app/features/orders/data/datasources/order_remote_datasource.dart';
import 'package:user_app/features/orders/domain/entities/order_enums.dart';

/// The timeline must show ONLY what actually happened.
///
/// Two fabrications used to leak in: every flow rung at or below the current
/// status was ticked (`idx >= i`) even when the store legitimately skipped it —
/// so a customer saw "Packed ✓" on an order nobody packed — and the no-events
/// fallback stamped invented `placedAt + 15/30/45 min` timestamps that rendered
/// exactly like real history.
class _StubApiClient implements ApiClient {
  _StubApiClient(this.body);

  final Map<String, dynamic> body;

  @override
  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? query,
      Options? options,
      CancelToken? cancelToken}) async {
    return Response<T>(
        requestOptions: RequestOptions(path: path), data: {'data': body} as T);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('unexpected ${invocation.memberName}');
}

// The real production payload shape (VSORD100008): the store jumped
// confirmed → ready_for_dispatch → out_for_delivery, never packing.
Map<String, dynamic> _order({
  String status = 'out_for_delivery',
  List<Map<String, dynamic>>? timeline,
}) =>
    {
      'id': 'VSORD100008',
      'status': status,
      'placedAt': '2026-07-22T14:15:28+05:30',
      'total': 649.0,
      'items': const <dynamic>[],
      'timeline': timeline ??
          [
            {'status': 'confirmed', 'at': '2026-07-22T14:15:28+05:30'},
            {'status': 'ready_for_dispatch', 'at': '2026-07-22T14:16:53+05:30'},
            {'status': 'out_for_delivery', 'at': '2026-07-22T14:17:34+05:30'},
          ],
    };

void main() {
  group('order timeline honesty', () {
    test('a skipped rung is NOT shown as done', () async {
      final ds = OrderRemoteDataSource(_StubApiClient(_order()));
      final order = await ds.detail('VSORD100008');

      final packed = order.timeline
          .where((e) => e.status == OrderStatus.packed)
          .toList();
      // The store never packed: either the rung is absent from history or, if
      // rendered as an upcoming step, it must be unticked. Never a done tick.
      for (final entry in packed) {
        expect(entry.done, isFalse,
            reason: 'Packed was never recorded but rendered as done');
      }
    });

    test('every done entry carries only a REAL recorded time (or none)',
        () async {
      final ds = OrderRemoteDataSource(_StubApiClient(_order()));
      final order = await ds.detail('VSORD100008');

      final real = {
        DateTime.parse('2026-07-22T14:15:28+05:30'),
        DateTime.parse('2026-07-22T14:16:53+05:30'),
        DateTime.parse('2026-07-22T14:17:34+05:30'),
      };
      for (final entry in order.timeline.where((e) => e.at != null)) {
        expect(real.any((t) => t.isAtSameMomentAs(entry.at!)), isTrue,
            reason: 'invented timestamp ${entry.at} for ${entry.status}');
      }
    });

    test('recorded events appear with their real timestamps', () async {
      final ds = OrderRemoteDataSource(_StubApiClient(_order()));
      final order = await ds.detail('VSORD100008');

      final rfd = order.timeline
          .firstWhere((e) => e.status == OrderStatus.readyForDispatch);
      expect(rfd.done, isTrue);
      expect(
          rfd.at!.isAtSameMomentAs(
              DateTime.parse('2026-07-22T14:16:53+05:30')),
          isTrue);
    });

    test('future steps render unticked so the ladder still shows what is next',
        () async {
      final ds = OrderRemoteDataSource(_StubApiClient(_order()));
      final order = await ds.detail('VSORD100008');

      final delivered = order.timeline
          .firstWhere((e) => e.status == OrderStatus.delivered);
      expect(delivered.done, isFalse);
      expect(delivered.at, isNull);
    });

    test('a cancelled order shows no delivery ladder ahead', () async {
      final ds = OrderRemoteDataSource(_StubApiClient(_order(
        status: 'cancelled',
        timeline: [
          {'status': 'confirmed', 'at': '2026-07-22T14:15:28+05:30'},
          {'status': 'cancelled', 'at': '2026-07-22T14:20:00+05:30'},
        ],
      )));
      final order = await ds.detail('VSORD100008');

      expect(
          order.timeline.any(
              (e) => e.status == OrderStatus.delivered ||
                  e.status == OrderStatus.outForDelivery),
          isFalse,
          reason: 'a cancelled order must not advertise delivery steps');
      expect(order.timeline.any((e) => e.status == OrderStatus.cancelled && e.done),
          isTrue);
    });

    test('the no-events fallback invents NO timestamps', () async {
      final ds = OrderRemoteDataSource(_StubApiClient(
          _order(status: 'packed', timeline: const [])));
      final order = await ds.detail('VSORD100008');

      // Only the order-created milestone may carry a time (placedAt is real).
      for (final entry in order.timeline
          .where((e) => e.status != OrderStatus.pending)) {
        expect(entry.at, isNull,
            reason: 'fabricated time on ${entry.status} with no backend events');
      }
    });
  });
}

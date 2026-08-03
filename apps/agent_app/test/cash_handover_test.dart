import 'dart:convert';
import 'dart:typed_data';

import 'package:agent_app/core/api.dart';
import 'package:agent_app/core/token_store.dart';
import 'package:agent_app/features/cash/cash_data.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeTokenStore extends TokenStore {
  @override
  Future<String?> get access async => 't';
  @override
  Future<String?> get refresh async => null;
  @override
  Future<void> save({required String access, String? refresh}) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<bool> get isLoggedIn async => true;
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);
  final ResponseBody Function(RequestOptions o) handler;
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s,
          Future<void>? c) async =>
      handler(o);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, int status) =>
    ResponseBody.fromString(jsonEncode(body), status,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        });

Api _api(ResponseBody Function(RequestOptions) h) => Api(
      _FakeTokenStore(),
      dio: Dio(BaseOptions(
        baseUrl: 'http://test',
        validateStatus: (s) => s != null && s < 500,
      ))
        ..httpClientAdapter = _FakeAdapter(h),
      bare: Dio(),
    );

void main() {
  group('CashDeposit parsing', () {
    test('a UPI deposit is flagged online', () {
      final d = CashDeposit.fromJson({
        'id': '1', 'amount': '800.00', 'method': 'upi',
        'channel': 'online', 'status': 'verified',
      });
      expect(d.isOnline, isTrue);
      expect(d.status, DepositStatus.verified);
    });

    test('a physical deposit defaults to cash when channel is absent', () {
      final d = CashDeposit.fromJson({
        'id': '2', 'amount': '500.00', 'method': 'office', 'status': 'pending',
      });
      expect(d.isOnline, isFalse);
      expect(d.channel, 'cash');
    });

    test('parses the new initiated / cancelled statuses', () {
      expect(
        CashDeposit.fromJson({'id': '3', 'amount': '1', 'status': 'initiated'})
            .status,
        DepositStatus.initiated,
      );
      expect(
        CashDeposit.fromJson({'id': '4', 'amount': '1', 'status': 'cancelled'})
            .status,
        DepositStatus.cancelled,
      );
    });

    test('an unknown status degrades to pending, not a crash', () {
      expect(
        CashDeposit.fromJson({'id': '5', 'amount': '1', 'status': 'weird'})
            .status,
        DepositStatus.pending,
      );
    });
  });

  group('CashApi.declareOnline', () {
    test('reads the nested payment block off the real response envelope',
        () async {
      final api = _api((o) {
        expect(o.path, '/agent/cash/online');
        return _json({
          'success': true,
          'data': {
            'id': '9',
            'amount': '800.00',
            'status': 'initiated',
            'channel': 'online',
            'payment': {
              'paymentId': '42',
              'shortUrl': 'https://rzp.io/i/abc',
              'status': 'pending',
            },
          },
        }, 201);
      });
      final h = await CashApi(api).declareOnline(collectionIds: ['1', '2']);
      expect(h.depositId, '9');
      expect(h.paymentId, '42');
      expect(h.shortUrl, 'https://rzp.io/i/abc');
      expect(h.amount, 800.00);
      expect(h.confirmed, isFalse);
    });

    test('a trusted-mock instant settle reports confirmed', () async {
      final api = _api((_) => _json({
            'data': {
              'id': '9', 'amount': '500.00', 'status': 'verified',
              'payment': {'paymentId': '42', 'shortUrl': '', 'status': 'success'},
            }
          }, 201));
      final h = await CashApi(api).declareOnline(collectionIds: ['1']);
      expect(h.confirmed, isTrue);
    });
  });

  group('CashApi.confirmOnline', () {
    test('posts to the deposit-scoped confirm path and parses the deposit',
        () async {
      final api = _api((o) {
        expect(o.path, '/agent/cash/online/9/confirm');
        expect(o.method, 'POST');
        return _json({
          'data': {
            'id': '9', 'amount': '800.00', 'method': 'upi',
            'channel': 'online', 'status': 'verified',
          }
        }, 200);
      });
      final d = await CashApi(api).confirmOnline('9');
      expect(d.status, DepositStatus.verified);
      expect(d.isOnline, isTrue);
    });
  });
}

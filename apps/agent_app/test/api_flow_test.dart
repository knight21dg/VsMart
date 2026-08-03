import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:agent_app/core/api.dart';
import 'package:agent_app/core/api_exception.dart';
import 'package:agent_app/core/token_store.dart';
import 'package:agent_app/features/dashboard/data/dashboard_data.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [TokenStore] (overrides every method so secure storage is unused).
class FakeTokenStore extends TokenStore {
  FakeTokenStore({this.a, this.r});
  String? a;
  String? r;
  @override
  Future<String?> get access async => a;
  @override
  Future<String?> get refresh async => r;
  @override
  Future<void> save({required String access, String? refresh}) async {
    a = access;
    if (refresh != null) r = refresh;
  }

  @override
  Future<void> clear() async {
    a = null;
    r = null;
  }

  @override
  Future<bool> get isLoggedIn async => (a ?? '').isNotEmpty;
}

/// Dio adapter that returns a canned response computed from the request.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);
  final ResponseBody Function(RequestOptions o) handler;
  @override
  Future<ResponseBody> fetch(RequestOptions options,
          Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async =>
      handler(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Map<String, dynamic> body, int status) =>
    ResponseBody.fromString(jsonEncode(body), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });

Dio _dio(ResponseBody Function(RequestOptions) h) => Dio(BaseOptions(
      baseUrl: 'http://test',
      validateStatus: (s) => s != null && s < 500,
    ))
  ..httpClientAdapter = FakeAdapter(h);

void main() {
  test('4xx no longer parses as success — repo throws a coded ApiException', () async {
    final api = Api(
      FakeTokenStore(a: 't'),
      dio: _dio((_) => _json({'code': 'CREDIT_FROZEN', 'message': 'Frozen.'}, 403)),
      bare: Dio(),
    );
    final repo = DashboardRepo(api);
    await expectLater(
      repo.me(),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'CREDIT_FROZEN')
          .having((e) => e.statusCode, 'status', 403)),
    );
  });

  test('2xx envelope parses into the model', () async {
    final api = Api(
      FakeTokenStore(a: 't'),
      dio: _dio((_) => _json({
            'success': true,
            'data': {'id': '1', 'name': 'Ravi', 'is_available': true}
          }, 200)),
      bare: Dio(),
    );
    final profile = await DashboardRepo(api).me();
    expect(profile.id, '1');
    expect(profile.isAvailable, isTrue);
  });

  test('401 triggers refresh + retry, persists the new token', () async {
    final tokens = FakeTokenStore(a: 'old', r: 'refresh-token');
    final api = Api(
      tokens,
      // main client: the original request always 401s
      dio: _dio((_) => _json({'code': 'SESSION_EXPIRED'}, 401)),
      // bare client: serves the refresh, then the retried request
      bare: _dio((o) => o.path.contains('/auth/refresh')
          ? _json({'access_token': 'new', 'refresh_token': 'r2'}, 200)
          : _json({'data': {'id': '9', 'name': 'A'}}, 200)),
    );
    final profile = await DashboardRepo(api).me();
    expect(profile.id, '9');
    expect(await tokens.access, 'new'); // refreshed + saved
  });

  test('refresh failure clears tokens and fires onLogout', () async {
    var loggedOut = false;
    final tokens = FakeTokenStore(a: 'old', r: 'bad');
    final api = Api(
      tokens,
      dio: _dio((_) => _json({'code': 'SESSION_EXPIRED'}, 401)),
      // refresh returns no access_token → refresh fails
      bare: _dio((_) => _json({}, 200)),
      onLogout: () async => loggedOut = true,
    );
    await expectLater(DashboardRepo(api).me(), throwsA(isA<ApiException>()));
    expect(loggedOut, isTrue);
    expect(await tokens.access, isNull);
  });
}

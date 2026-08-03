import 'package:dio/dio.dart';

import 'api.dart';

abstract class BaseRepository {
  BaseRepository(this._api);

  final Api _api;

  Response<dynamic> ensureOk(Response<dynamic> res) => _api.ensureOk(res);

  Map<String, dynamic> obj(dynamic raw) => _api.obj(raw);

  List<Map<String, dynamic>> list(dynamic raw) => _api.list(raw);

  Future<Response<dynamic>> get(String path, {bool noAuth = false}) =>
      _api.get(path, noAuth: noAuth);

  Future<Response<dynamic>> post(String path,
          {Object? data, bool noAuth = false}) =>
      _api.post(path, data: data, noAuth: noAuth);

  Future<Response<dynamic>> put(String path,
          {Object? data, bool noAuth = false}) =>
      _api.put(path, data: data, noAuth: noAuth);

  Future<Response<dynamic>> patch(String path,
          {Object? data, bool noAuth = false}) =>
      _api.patch(path, data: data, noAuth: noAuth);

  Future<Response<dynamic>> postMultipart(String path, FormData form,
          {bool noAuth = false}) =>
      _api.postMultipart(path, form, noAuth: noAuth);

  Future<List<int>> bytes(String path) => _api.bytes(path);
}

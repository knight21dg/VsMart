import 'package:hive_flutter/hive_flutter.dart';
import 'package:user_app/app/constants/storage_keys.dart';
import 'package:user_app/core/storage/hive_service.dart';

/// In-memory Hive [Box] for tests — only the get/put/delete the app actually uses
/// are real; everything else routes to noSuchMethod (unused in unit tests).
class FakeBox implements Box<dynamic> {
  final Map<dynamic, dynamic> _data = {};

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      _data.containsKey(key) ? _data[key] : defaultValue;

  @override
  Future<void> put(dynamic key, dynamic value) async => _data[key] = value;

  @override
  Future<void> delete(dynamic key) async => _data.remove(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fake [HiveService] backed by in-memory boxes. Reusable for any Hive-backed
/// controller (checkout draft, cart, settings, …).
class FakeHiveService implements HiveService {
  final Map<String, FakeBox> _boxes = {};

  FakeBox boxFor(String name) => _boxes.putIfAbsent(name, FakeBox.new);

  @override
  Box<dynamic> box(String name) => boxFor(name);

  // Named-box getters used by controllers (HiveService exposes these).
  @override
  Box<dynamic> get userBox => boxFor(StorageKeys.userBox);
  @override
  Box<dynamic> get cartBox => boxFor(StorageKeys.cartBox);
  @override
  Box<dynamic> get cacheBox => boxFor(StorageKeys.cacheBox);
  @override
  Box<dynamic> get settingsBox => boxFor(StorageKeys.settingsBox);
  @override
  Box<dynamic> get verificationBox => boxFor(StorageKeys.verificationBox);
  @override
  Box<dynamic> get addressBox => boxFor(StorageKeys.addressBox);
  @override
  Box<dynamic> get recentlyViewedBox => boxFor(StorageKeys.recentlyViewedBox);
  @override
  Box<dynamic> get orderBox => boxFor(StorageKeys.orderBox);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

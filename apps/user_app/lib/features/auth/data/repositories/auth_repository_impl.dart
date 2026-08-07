import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/base_repository.dart';
import '../../../../core/network/network_info.dart';
import '../../../../core/storage/hive_service.dart';
import '../../domain/entities/auth_token.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_local_datasource.dart';
import '../datasources/auth_remote_datasource.dart';

class AuthRepositoryImpl with BaseRepository implements AuthRepository {
  AuthRepositoryImpl({
    required this.remote,
    required this.local,
    required this.networkInfo,
  });

  final AuthRemoteDataSource remote;
  final AuthLocalDataSource local;

  @override
  final NetworkInfo networkInfo;

  @override
  Future<Either<Failure, User>> register({
    required String name,
    String? email,
    String? referralCode,
  }) =>
      guard(() async {
        final model = await remote.register(
          name: name,
          email: email,
          referralCode: referralCode,
        );
        await local.cacheUser(model);
        return model.toEntity();
      });

  @override
  Future<Either<Failure, Unit>> persistSession(AuthToken token) =>
      guard(requireConnection: false, () async {
        await local.saveToken(token);
        return unit;
      });

  @override
  Future<bool> hasValidSession() => local.hasValidToken();

  @override
  Future<Either<Failure, Unit>> logout() =>
      guard(requireConnection: false, () async {
        // Best-effort server revoke; ignore network errors.
        try {
          if (await networkInfo.isConnected) await remote.logout();
        } catch (_) {/* ignore */}
        await local.clear();
        // Wipe every user-scoped Hive box so nothing leaks to the next account.
        await HiveService.instance.clearAll();
        return unit;
      });
}

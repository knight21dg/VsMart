import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/base_repository.dart';
import '../../../../core/network/network_info.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/user_repository.dart';
import '../datasources/auth_local_datasource.dart';
import '../datasources/auth_remote_datasource.dart';

class UserRepositoryImpl with BaseRepository implements UserRepository {
  UserRepositoryImpl({
    required this.remote,
    required this.local,
    required this.networkInfo,
  });

  final AuthRemoteDataSource remote;
  final AuthLocalDataSource local;

  @override
  final NetworkInfo networkInfo;

  @override
  Future<Either<Failure, User>> getCurrentUser() => guard(() async {
        final model = await remote.getCurrentUser();
        await local.cacheUser(model);
        return model.toEntity();
      });

  @override
  User? getCachedUser() => local.getCachedUser()?.toEntity();

  @override
  Future<Either<Failure, User>> updateProfile({
    String? name,
    String? email,
    String? avatarUrl,
  }) =>
      guard(() async {
        final model = await remote.updateProfile({
          if (name != null) 'name': name,
          if (email != null) 'email': email,
          if (avatarUrl != null) 'avatar_url': avatarUrl,
        });
        await local.cacheUser(model);
        return model.toEntity();
      });
}

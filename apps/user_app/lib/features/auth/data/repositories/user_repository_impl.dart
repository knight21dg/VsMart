import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/base_repository.dart';
import '../../../../core/network/network_info.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/user_repository.dart';
import '../datasources/auth_local_datasource.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/user_model.dart';

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
    String? gender,
    DateTime? dateOfBirth,
  }) =>
      guard(() async {
        final model = await remote.updateProfile({
          if (name != null) 'name': name,
          if (email != null) 'email': email,
          if (avatarUrl != null) 'avatar_url': avatarUrl,
          if (gender != null) 'gender': gender,
          if (dateOfBirth != null) 'date_of_birth': _isoDate(dateOfBirth),
        });
        await local.cacheUser(model);
        return model.toEntity();
      });

  @override
  Future<Either<Failure, User>> uploadAvatar(String filePath) => guard(() async {
        final avatarUrl = await remote.uploadAvatar(filePath);
        // Merge the new URL into the cached user so the whole app reflects it
        // without a second round-trip.
        final cached = local.getCachedUser();
        final updated = (cached?.toEntity() ?? const User(id: '', phone: ''))
            .copyWith(avatarUrl: avatarUrl);
        await local.cacheUser(UserModel.fromEntity(updated));
        return updated;
      });

  /// Serialize a date as the backend's `yyyy-MM-dd` (date-only) contract.
  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

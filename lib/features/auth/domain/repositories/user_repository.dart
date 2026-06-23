import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/user.dart';

/// Current-user profile operations.
abstract interface class UserRepository {
  /// Fetch the authenticated user's profile from the backend.
  Future<Either<Failure, User>> getCurrentUser();

  /// Read the locally cached user, if any (for instant cold-start render).
  User? getCachedUser();

  /// Update editable profile fields.
  Future<Either<Failure, User>> updateProfile({
    String? name,
    String? email,
    String? avatarUrl,
  });
}

import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/usecase.dart';
import '../entities/user.dart';
import '../repositories/user_repository.dart';

/// Fetches the authenticated user's profile.
class GetCurrentUser implements UseCase<User, NoParams> {
  const GetCurrentUser(this._repository);

  final UserRepository _repository;

  @override
  Future<Either<Failure, User>> call(NoParams params) =>
      _repository.getCurrentUser();
}

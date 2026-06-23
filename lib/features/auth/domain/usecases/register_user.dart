import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/usecase.dart';
import '../entities/user.dart';
import '../repositories/auth_repository.dart';

class RegisterParams extends Equatable {
  const RegisterParams({required this.name, this.email, this.referralCode});

  final String name;
  final String? email;
  final String? referralCode;

  @override
  List<Object?> get props => [name, email, referralCode];
}

/// Completes profile registration after phone verification.
class RegisterUser implements UseCase<User, RegisterParams> {
  const RegisterUser(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, User>> call(RegisterParams params) => _repository.register(
        name: params.name,
        email: params.email,
        referralCode: params.referralCode,
      );
}

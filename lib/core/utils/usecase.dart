import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import '../errors/failures.dart';

/// Base contract for an application use case.
///
/// [Type] is the success value; [Params] is the input (use [NoParams] for none).
abstract interface class UseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}

/// Synchronous use case variant (no Future).
abstract interface class SyncUseCase<Type, Params> {
  Either<Failure, Type> call(Params params);
}

/// Sentinel for use cases that take no parameters.
class NoParams extends Equatable {
  const NoParams();

  @override
  List<Object?> get props => [];
}

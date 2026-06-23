import 'package:dartz/dartz.dart';

import '../errors/error_handler.dart';
import '../errors/failures.dart';
import 'network_info.dart';

/// Mixin providing a safe execution helper for repository implementations.
///
/// Wraps a remote call in try/catch, converts thrown errors into [Failure]s,
/// and optionally guards on connectivity first.
mixin BaseRepository {
  NetworkInfo get networkInfo;

  /// Run [action], returning `Right(value)` on success or `Left(Failure)` on
  /// error. When [requireConnection] is true, short-circuits to
  /// [NetworkFailure] if the device is offline.
  Future<Either<Failure, T>> guard<T>(
    Future<T> Function() action, {
    bool requireConnection = true,
  }) async {
    if (requireConnection && !await networkInfo.isConnected) {
      return const Left(NetworkFailure());
    }
    try {
      return Right(await action());
    } catch (e) {
      return Left(ErrorHandler.handle(e));
    }
  }
}

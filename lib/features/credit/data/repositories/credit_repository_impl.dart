import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/base_repository.dart';
import '../../../../core/network/network_info.dart';
import '../../domain/entities/credit_account.dart';
import '../../domain/entities/credit_payment_result.dart';
import '../../domain/entities/credit_transaction.dart';
import '../../domain/repositories/credit_repository.dart';
import '../datasources/credit_data_source.dart';

/// [CreditRepository] backed by a [CreditDataSource]. Errors normalise to
/// [Failure] via [BaseRepository.guard]. Reads tolerate offline use via the
/// cached snapshot; the backend remains the source of truth.
class CreditRepositoryImpl with BaseRepository implements CreditRepository {
  CreditRepositoryImpl({required this.dataSource, required this.networkInfo});

  final CreditDataSource dataSource;

  @override
  final NetworkInfo networkInfo;

  @override
  Future<Either<Failure, CreditAccount>> getAccount() =>
      guard(dataSource.getAccount, requireConnection: false);

  @override
  Future<Either<Failure, List<CreditTransaction>>> getTransactions() =>
      guard(dataSource.getTransactions, requireConnection: false);

  @override
  Future<Either<Failure, CreditPaymentResult>> makePayment({
    required num amount,
    required String method,
  }) =>
      guard(() => dataSource.makePayment(amount: amount, method: method),
          requireConnection: false);
}

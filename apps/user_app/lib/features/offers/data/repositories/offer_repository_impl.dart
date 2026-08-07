import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/base_repository.dart';
import '../../../../core/network/network_info.dart';
import '../../domain/entities/offer.dart';
import '../../domain/repositories/offer_repository.dart';
import '../datasources/offer_data_source.dart';

/// [OfferRepository] backed by an [OfferDataSource], normalising errors to
/// [Failure] via [BaseRepository.guard].
class OfferRepositoryImpl with BaseRepository implements OfferRepository {
  OfferRepositoryImpl({required this.dataSource, required this.networkInfo});

  final OfferDataSource dataSource;

  @override
  final NetworkInfo networkInfo;

  @override
  Future<Either<Failure, List<Offer>>> getBanners() =>
      guard(dataSource.getBanners, requireConnection: false);

  @override
  Future<Either<Failure, List<Offer>>> getDeals() =>
      guard(dataSource.getDeals, requireConnection: false);

  @override
  Future<Either<Failure, List<Offer>>> getCoupons() =>
      guard(dataSource.getCoupons, requireConnection: false);
}

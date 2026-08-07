import 'package:dartz/dartz.dart';

import '../../../../core/errors/failures.dart';
import '../entities/offer.dart';

/// Promotions: home banners, time-boxed deals, and coupons.
abstract interface class OfferRepository {
  /// Carousel banners for the home screen.
  Future<Either<Failure, List<Offer>>> getBanners();

  /// "Today's deals" — discounted, time-boxed products.
  Future<Either<Failure, List<Offer>>> getDeals();

  /// Coupons available in the customer's wallet.
  Future<Either<Failure, List<Offer>>> getCoupons();
}

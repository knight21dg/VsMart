import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/core_providers.dart';
import '../../data/reviews_data.dart';

final reviewsDataSourceProvider = Provider<ReviewsRemoteDataSource>(
  (ref) => ReviewsRemoteDataSource(ref.watch(apiClientProvider)),
);

/// A product's reviews + rating summary, keyed by product id (public).
final productReviewsProvider =
    FutureProvider.family<ProductReviews, String>(
  (ref, productId) =>
      ref.watch(reviewsDataSourceProvider).getForProduct(productId),
);

/// The signed-in user's own reviews (auth).
final myReviewsProvider = FutureProvider<List<Review>>(
  (ref) => ref.watch(reviewsDataSourceProvider).myReviews(),
);

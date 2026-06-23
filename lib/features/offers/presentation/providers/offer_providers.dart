import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../data/datasources/caching_offer_data_source.dart';
import '../../data/datasources/offer_backend_data_source.dart';
import '../../data/datasources/offer_data_source.dart';
import '../../data/repositories/offer_repository_impl.dart';
import '../../domain/entities/offer.dart';
import '../../domain/repositories/offer_repository.dart';

T _unwrap<T>(Either<Failure, T> either) =>
    either.fold((f) => throw f, (value) => value);

final offerRemoteDataSourceProvider = Provider<OfferDataSource>(
  (ref) => OfferBackendDataSource(ref.watch(apiClientProvider)),
);

/// Stale-while-revalidate caching source used by the repository.
final offerDataSourceProvider = Provider<OfferDataSource>(
  (ref) => CachingOfferDataSource(
    remote: ref.watch(offerRemoteDataSourceProvider),
    cache: ref.watch(commerceCacheManagerProvider),
  ),
);

final offerRepositoryProvider = Provider<OfferRepository>(
  (ref) => OfferRepositoryImpl(
    dataSource: ref.watch(offerDataSourceProvider),
    networkInfo: ref.watch(networkInfoProvider),
  ),
);

final bannersProvider = FutureProvider<List<Offer>>(
  (ref) async => _unwrap(await ref.watch(offerRepositoryProvider).getBanners()),
);

final dealsProvider = FutureProvider<List<Offer>>(
  (ref) async => _unwrap(await ref.watch(offerRepositoryProvider).getDeals()),
);

final couponsProvider = FutureProvider<List<Offer>>(
  (ref) async => _unwrap(await ref.watch(offerRepositoryProvider).getCoupons()),
);

/// Targeting key for [placementBannersProvider]: the screen placement plus the
/// optional category / sub-category to scope banners to.
typedef BannerTarget = ({
  String placement,
  String? categoryId,
  String? subcategoryId,
});

/// Banners targeted at a screen placement (`product_list`, `product_detail`),
/// scoped by category/sub-category, with a marketing fallback supplied by the
/// server. Bypasses the home-banner cache (these are screen-specific) and
/// never throws into the UI — returns an empty list on any error so callers
/// can render nothing.
final placementBannersProvider =
    FutureProvider.autoDispose.family<List<Offer>, BannerTarget>(
  (ref, target) async {
    final source = ref.watch(offerRemoteDataSourceProvider);
    if (source is! OfferBackendDataSource) return const [];
    return source.getPlacementBanners(
      placement: target.placement,
      categoryId: target.categoryId,
      subcategoryId: target.subcategoryId,
    );
  },
);

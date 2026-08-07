import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../../shared/providers/location_scope_provider.dart';
import '../../data/datasources/caching_offer_data_source.dart';
import '../../data/datasources/offer_backend_data_source.dart';
import '../../data/datasources/offer_data_source.dart';
import '../../data/repositories/offer_repository_impl.dart';
import '../../domain/entities/offer.dart';
import '../../domain/repositories/offer_repository.dart';

T _unwrap<T>(Either<Failure, T> either) =>
    either.fold((f) => throw f, (value) => value);

final offerRemoteDataSourceProvider = Provider<OfferDataSource>(
  (ref) {
    // Send the customer's location so the backend returns only the banners valid
    // for their serving zone/store (targeting + in-stock filtering, server-side).
    //
    // Uses the SHARED location scope — this used to read only the saved address,
    // so a customer with no saved address (new user, guest, or a GPS-only
    // session) sent no location at all and the backend fell through to the global
    // banner set: promotions for other cities, deals on products their store
    // doesn't carry.
    final scope = ref.watch(locationScopeProvider);
    return OfferBackendDataSource(
      ref.watch(apiClientProvider),
      lat: scope.lat,
      lng: scope.lng,
      pincode: scope.pincode,
    );
  },
);

/// Stale-while-revalidate caching source used by the repository.
///
/// Namespaced by the serving store for the same reason as the catalog: the keys
/// were global (`banners`, `deals`, `coupons`), so changing zone kept showing the
/// previous zone's promotions out of Hive for the whole TTL.
final offerDataSourceProvider = Provider<OfferDataSource>(
  (ref) => CachingOfferDataSource(
    remote: ref.watch(offerRemoteDataSourceProvider),
    cache: ref.watch(commerceCacheManagerProvider),
    scope: ref.watch(locationScopeProvider).cacheKey,
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

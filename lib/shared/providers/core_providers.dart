import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/network/network_info.dart';
import '../../core/services/analytics_service.dart';
import '../../core/services/image_compression_service.dart';
import '../../core/services/location_service.dart';
import '../../core/storage/cache_manager.dart';
import '../../core/storage/cart_storage.dart';
import '../../core/storage/commerce_cache_manager.dart';
import '../../core/storage/hive_service.dart';
import '../../core/storage/local_user_storage.dart';
import '../../core/storage/secure_storage.dart';
import '../../core/storage/token_storage.dart';
import '../../features/auth/presentation/providers/session_provider.dart';

/// ---------------------------------------------------------------------------
/// Core singletons (storage, network, services) exposed to the whole app.
///
/// [HiveService.init] must run during bootstrap before these are first read.
/// ---------------------------------------------------------------------------

final hiveServiceProvider = Provider<HiveService>((ref) => HiveService.instance);

final secureStorageProvider =
    Provider<SecureStorage>((ref) => SecureStorage.create());

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => TokenStorage(ref.watch(secureStorageProvider)),
);

final localUserStorageProvider = Provider<LocalUserStorage>(
  (ref) => LocalUserStorage(ref.watch(hiveServiceProvider)),
);

final cartStorageProvider = Provider<CartStorage>(
  (ref) => CartStorage(ref.watch(hiveServiceProvider)),
);

final cacheManagerProvider = Provider<CacheManager>(
  (ref) => CacheManager(ref.watch(hiveServiceProvider)),
);

final connectivityProvider = Provider<Connectivity>((ref) => Connectivity());

final networkInfoProvider = Provider<NetworkInfo>(
  (ref) => NetworkInfoImpl(ref.watch(connectivityProvider)),
);

/// Reactive online/offline stream.
final connectivityStatusProvider = StreamProvider<bool>(
  (ref) => ref.watch(networkInfoProvider).onConnectivityChanged,
);

/// Commerce-facing connectivity state for offline banners / sync indicators.
enum CommerceConnectivity { online, offline, syncing }

final commerceConnectivityProvider = Provider<CommerceConnectivity>((ref) {
  return ref.watch(connectivityStatusProvider).when(
        data: (online) =>
            online ? CommerceConnectivity.online : CommerceConnectivity.offline,
        loading: () => CommerceConnectivity.syncing,
        error: (_, __) => CommerceConnectivity.offline,
      );
});

/// Generic Hive-backed JSON cache for commerce data (stale-while-revalidate).
final commerceCacheManagerProvider = Provider<CommerceCacheManager>(
  (ref) => CommerceCacheManager(ref.watch(hiveServiceProvider)),
);

final locationServiceProvider =
    Provider<LocationService>((ref) => const LocationService());

final analyticsServiceProvider =
    Provider<AnalyticsService>((ref) => const AnalyticsService());

final imageCompressionServiceProvider =
    Provider<ImageCompressionService>((ref) => const ImageCompressionService());

/// Set true when a 401/refresh-failure forces a logout, so the login screen can
/// explain why ("your session expired") instead of silently bouncing the user.
/// The login screen resets it after showing the notice.
final sessionExpiredProvider = StateProvider<bool>((ref) => false);

/// Configured API client. On 401 it clears the local session, which flips the
/// router redirect back to the login flow.
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    tokenStorage: ref.watch(tokenStorageProvider),
    onUnauthorized: () async {
      await ref.read(sessionControllerProvider.notifier).clearLocalSession();
      ref.read(sessionExpiredProvider.notifier).state = true;
    },
  );
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/constants/app_constants.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../data/app_status.dart';
import '../../data/system_data_source.dart';

final systemDataSourceProvider = Provider<SystemRemoteDataSource>(
  (ref) => SystemRemoteDataSource(ref.watch(apiClientProvider)),
);

/// Bootstrap status (`/app-config`). Fails OPEN: on any error it resolves to
/// [AppStatus.open] so a flaky config call never blocks the whole app.
final appStatusProvider = FutureProvider<AppStatus>((ref) async {
  try {
    return await ref.watch(systemDataSourceProvider).getAppConfig();
  } catch (_) {
    return AppStatus.open;
  }
});

/// Whether the installed app is older than the backend-required minimum.
final forceUpdateProvider = Provider<bool>((ref) {
  final status = ref.watch(appStatusProvider).valueOrNull;
  if (status == null) return false;
  return isUpdateRequired(AppConstants.appVersion, status.minAppVersion);
});

/// Whether the backend is in maintenance mode.
final maintenanceProvider = Provider<bool>(
  (ref) => ref.watch(appStatusProvider).valueOrNull?.maintenance ?? false,
);

/// Read a single backend feature flag (defaults to false until config loads).
final featureFlagProvider = Provider.family<bool, String>(
  (ref, key) => ref.watch(appStatusProvider).valueOrNull?.flag(key) ?? false,
);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../shared/providers/core_providers.dart';
import '../../data/content_data.dart';

final contentDataSourceProvider = Provider<ContentRemoteDataSource>(
  (ref) => ContentRemoteDataSource(ref.watch(apiClientProvider)),
);

/// Fetches a single CMS page by its slug (about / contact / careers /
/// terms / privacy).
final contentPageProvider = FutureProvider.family<ContentPage, String>(
  (ref, slug) => ref.watch(contentDataSourceProvider).getPage(slug),
);

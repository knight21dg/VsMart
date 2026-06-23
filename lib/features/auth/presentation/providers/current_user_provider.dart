import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/usecase.dart';
import '../../domain/entities/user.dart';
import 'auth_provider.dart';
import 'session_provider.dart';

/// The currently authenticated user (or null when signed out). Sourced from the
/// session so it updates reactively across the app.
final currentUserProvider = Provider<User?>(
  (ref) => ref.watch(sessionControllerProvider).user,
);

/// Fetches the latest profile from the backend and syncs it into the session.
/// Watch this (e.g. on app start / profile screen) to keep the user fresh.
final refreshUserProvider = FutureProvider.autoDispose<User?>((ref) async {
  final session = ref.watch(sessionControllerProvider);
  if (!session.isAuthenticated) return null;

  final result = await ref.read(getCurrentUserProvider).call(const NoParams());
  return result.fold(
    (_) => session.user, // keep cached user on failure
    (user) {
      ref.read(sessionControllerProvider.notifier).setUser(user);
      return user;
    },
  );
});

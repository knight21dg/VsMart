import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../auth/presentation/providers/session_provider.dart';

/// Drives the "edit profile" save. `state` is the in-flight flag (mirrors the
/// pattern used by other VS controllers). On success it syncs the updated user
/// into the session so the whole app reflects the change immediately.
class EditProfileController extends Notifier<bool> {
  @override
  bool build() => false;

  /// Persist [name]/[email]. Returns `null` on success, otherwise the error
  /// message to surface to the user.
  Future<String?> save({required String name, String? email}) async {
    state = true;
    final result = await ref.read(userRepositoryProvider).updateProfile(
          name: name,
          email: email,
        );
    state = false;
    return result.fold(
      (failure) => failure.message,
      (user) {
        ref.read(sessionControllerProvider.notifier).setUser(user);
        return null;
      },
    );
  }
}

final editProfileControllerProvider =
    NotifierProvider<EditProfileController, bool>(EditProfileController.new);

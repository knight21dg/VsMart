import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/utils/usecase.dart';
import '../../../../shared/providers/core_providers.dart';
import '../../../../shared/providers/settings_provider.dart';
import '../../data/datasources/auth_local_datasource.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/repositories/otp_repository_impl.dart';
import '../../data/repositories/user_repository_impl.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/otp_repository.dart';
import '../../domain/repositories/user_repository.dart';
import '../../domain/usecases/get_current_user.dart';
import '../../domain/usecases/logout.dart';
import '../../domain/usecases/register_user.dart';
import '../../domain/usecases/send_otp.dart';
import '../../domain/usecases/verify_otp.dart';
import 'session_provider.dart';

/// ---------------------------------------------------------------------------
/// Data layer wiring
/// ---------------------------------------------------------------------------
final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>(
  (ref) => AuthRemoteDataSourceImpl(ref.watch(apiClientProvider)),
);

final authLocalDataSourceProvider = Provider<AuthLocalDataSource>(
  (ref) => AuthLocalDataSourceImpl(
    ref.watch(tokenStorageProvider),
    ref.watch(localUserStorageProvider),
  ),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(
    remote: ref.watch(authRemoteDataSourceProvider),
    local: ref.watch(authLocalDataSourceProvider),
    networkInfo: ref.watch(networkInfoProvider),
  ),
);

final otpRepositoryProvider = Provider<OtpRepository>(
  (ref) => OtpRepositoryImpl(
    remote: ref.watch(authRemoteDataSourceProvider),
    networkInfo: ref.watch(networkInfoProvider),
  ),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepositoryImpl(
    remote: ref.watch(authRemoteDataSourceProvider),
    local: ref.watch(authLocalDataSourceProvider),
    networkInfo: ref.watch(networkInfoProvider),
  ),
);

/// ---------------------------------------------------------------------------
/// Use cases
/// ---------------------------------------------------------------------------
final sendOtpProvider =
    Provider((ref) => SendOtp(ref.watch(otpRepositoryProvider)));
final verifyOtpProvider = Provider((ref) => VerifyOtp(
      ref.watch(otpRepositoryProvider),
      ref.watch(authRepositoryProvider),
    ));
final registerUserProvider =
    Provider((ref) => RegisterUser(ref.watch(authRepositoryProvider)));
final getCurrentUserProvider =
    Provider((ref) => GetCurrentUser(ref.watch(userRepositoryProvider)));
final logoutProvider =
    Provider((ref) => Logout(ref.watch(authRepositoryProvider)));

/// ---------------------------------------------------------------------------
/// Auth flow controller (OTP login / registration)
/// ---------------------------------------------------------------------------
class AuthFlowState extends Equatable {
  const AuthFlowState({
    this.isLoading = false,
    this.otpSent = false,
    this.phone,
    this.verificationId,
    this.isNewUser = false,
    this.failure,
  });

  final bool isLoading;
  final bool otpSent;
  final String? phone;
  final String? verificationId;
  final bool isNewUser;
  final Failure? failure;

  AuthFlowState copyWith({
    bool? isLoading,
    bool? otpSent,
    String? phone,
    String? verificationId,
    bool? isNewUser,
    Failure? failure,
    bool clearFailure = false,
  }) {
    return AuthFlowState(
      isLoading: isLoading ?? this.isLoading,
      otpSent: otpSent ?? this.otpSent,
      phone: phone ?? this.phone,
      verificationId: verificationId ?? this.verificationId,
      isNewUser: isNewUser ?? this.isNewUser,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props =>
      [isLoading, otpSent, phone, verificationId, isNewUser, failure];
}

class AuthController extends Notifier<AuthFlowState> {
  @override
  AuthFlowState build() => const AuthFlowState();

  /// Demo mode: accept ANY mobile number / OTP without a backend round-trip.
  /// Now OFF — the app performs the real OTP flow against the backend. In dev you
  /// can log in with any number using the master code `123456`.
  // ignore: prefer_const_declarations
  static final bool _acceptAnyCredentials = false;

  /// Request an OTP for [phone]. Returns true on success.
  Future<bool> sendOtp(String phone) async {
    state = state.copyWith(isLoading: true, clearFailure: true, phone: phone);

    // Demo mode: skip the network and pretend an OTP was delivered.
    if (_acceptAnyCredentials) {
      state = state.copyWith(
        isLoading: false,
        otpSent: true,
        verificationId: 'demo-verification',
      );
      return true;
    }

    final result = await ref.read(sendOtpProvider).call(phone);
    return result.fold(
      (f) {
        state = state.copyWith(isLoading: false, failure: f);
        return false;
      },
      (verificationId) {
        state = state.copyWith(
          isLoading: false,
          otpSent: true,
          verificationId: verificationId,
        );
        return true;
      },
    );
  }

  /// Verify [code] for the current phone. On success the session is set
  /// authenticated and the new-user flag is exposed for routing to register/KYC.
  Future<bool> verifyOtp(String code) async {
    final phone = state.phone;
    if (phone == null) return false;
    state = state.copyWith(isLoading: true, clearFailure: true);

    // Demo mode: any code logs the user straight in as a fully-approved
    // returning customer so routing lands on Home (no KYC gate).
    if (_acceptAnyCredentials) {
      state = state.copyWith(isLoading: false, isNewUser: false);
      ref
          .read(sessionControllerProvider.notifier)
          .setAuthenticated(_demoUser(phone));
      return true;
    }

    final result = await ref.read(verifyOtpProvider).call(
          VerifyOtpParams(
            phone: phone,
            code: code,
            verificationId: state.verificationId,
          ),
        );

    return result.fold(
      (f) async {
        state = state.copyWith(isLoading: false, failure: f);
        return false;
      },
      (auth) async {
        state = state.copyWith(isLoading: false, isNewUser: auth.isNewUser);
        // Real sign-in — leave guest mode so the app routes as an account holder.
        await ref.read(guestModeProvider.notifier).disable();
        // Pull the freshest profile (or fall back to a minimal session user).
        final userResult =
            await ref.read(getCurrentUserProvider).call(const NoParams());
        userResult.fold(
          (_) => ref
              .read(sessionControllerProvider.notifier)
              .setAuthenticated(_minimalUser(phone)),
          (user) => ref
              .read(sessionControllerProvider.notifier)
              .setAuthenticated(user),
        );
        return true;
      },
    );
  }

  /// Complete registration for a new user (name + optional referral code).
  Future<bool> register({
    required String name,
    String? email,
    String? referralCode,
  }) async {
    state = state.copyWith(isLoading: true, clearFailure: true);
    final result = await ref.read(registerUserProvider).call(
          RegisterParams(name: name, email: email, referralCode: referralCode),
        );
    return result.fold(
      (f) {
        state = state.copyWith(isLoading: false, failure: f);
        return false;
      },
      (user) {
        state = state.copyWith(isLoading: false);
        ref.read(sessionControllerProvider.notifier).setUser(user);
        return true;
      },
    );
  }

  Future<void> logout() async {
    await ref.read(logoutProvider).call(const NoParams());
    await ref.read(sessionControllerProvider.notifier).clearLocalSession();
    state = const AuthFlowState();
  }

  void reset() => state = const AuthFlowState();
}

/// A minimal user built from just the phone, used if the profile fetch fails
/// right after verification (e.g. a brand-new account with no profile yet).
User _minimalUser(String phone) =>
    User(id: phone, phone: phone, kycStatus: KycStatus.notStarted);

/// Demo-mode user: a fully-approved customer derived from the entered [phone]
/// so the "accept any number/OTP" login lands straight on Home.
User _demoUser(String phone) => User(
      id: phone,
      phone: phone,
      name: 'VS Mart Customer',
      kycStatus: KycStatus.verified,
      creditEnabled: true,
    );

final authControllerProvider =
    NotifierProvider<AuthController, AuthFlowState>(AuthController.new);

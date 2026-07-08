import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/result.dart';
import '../data/auth_repository.dart';
import '../data/last_email_store.dart';

/// Drives auth actions and surfaces their outcome as an [AsyncValue].
///
/// `build` returns nothing — this controller models *actions* (sign in/up/out,
/// shop creation), not a piece of loaded state. Screens watch its `isLoading`
/// to disable buttons and `ref.listen` for `AsyncError` to show messages.
class AuthController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  AuthRepository get _repo => ref.read(authRepositoryProvider);

  Future<void> _run(Future<Result<void>> Function() action) async {
    state = const AsyncLoading();
    final result = await action();
    state = result.when(
      success: (_) => const AsyncData(null),
      failure: (f) => AsyncError(f, StackTrace.current),
    );
  }

  Future<void> signInWithEmail(String email, String password) => _run(() async {
    final result = await _repo.signInWithEmail(email.trim(), password);
    if (result.isSuccess) {
      await ref.read(lastEmailStoreProvider).save(email);
    }
    return result;
  });

  Future<void> signUpWithEmail(
    String email,
    String password, {
    String? fullName,
  }) => _run(() async {
    final result = await _repo.signUpWithEmail(
      email.trim(),
      password,
      fullName: fullName?.trim(),
    );
    if (result.isSuccess) {
      await ref.read(lastEmailStoreProvider).save(email);
    }
    return result;
  });

  Future<void> signInWithGoogle() => _run(_repo.signInWithGoogle);

  /// Dev-only guest sign in (see [AuthRepository.signInAnonymously]).
  Future<void> signInAsGuest() => _run(_repo.signInAnonymously);

  Future<void> signOut() => _run(_repo.signOut);

  /// Creates the user's shop, then refreshes [myShopProvider] so the router
  /// moves them off the profile-setup step.
  Future<void> createShop({
    required String name,
    String? address,
    String? phone,
  }) async {
    state = const AsyncLoading();
    final result = await _repo.createShop(
      name: name.trim(),
      address: address?.trim(),
      phone: phone?.trim(),
    );
    state = result.when(
      success: (_) {
        ref.invalidate(myShopProvider);
        return const AsyncData(null);
      },
      failure: (f) => AsyncError(f, StackTrace.current),
    );
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, void>(
  AuthController.new,
);

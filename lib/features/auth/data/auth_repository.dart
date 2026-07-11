import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../domain/shop.dart';

/// Wraps all Supabase Auth + shop-bootstrap calls. Repositories are the only
/// layer that touch the Supabase client; controllers call into here and never
/// see raw SDK exceptions — everything comes back as [Result].
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  User? get currentUser => _auth.currentUser;

  /// Email + password sign in.
  Future<Result<void>> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithPassword(email: email, password: password);
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Email + password sign up. `fullName` is stored in user metadata and copied
  /// into public.users by the `handle_new_user` trigger.
  Future<Result<void>> signUpWithEmail(
    String email,
    String password, {
    String? fullName,
  }) async {
    try {
      await _auth.signUp(
        email: email,
        password: password,
        data: fullName == null ? null : {'full_name': fullName},
      );
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Google OAuth sign in.
  ///
  /// Requires (config, not code): the Google provider enabled in Supabase Auth
  /// and a deep-link redirect registered for this app. The resulting session
  /// arrives asynchronously via `onAuthStateChange`.
  Future<Result<void>> signInWithGoogle() async {
    try {
      await _auth.signInWithOAuth(OAuthProvider.google);
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Anonymous (guest) sign in — dev convenience to bypass email/password.
  /// Creates a real auth session with a valid `auth.uid()`, so RLS-scoped
  /// inventory/shop/sales all work. Requires "Anonymous sign-ins" enabled in
  /// the Supabase dashboard (Authentication → Sign In / Providers).
  Future<Result<void>> signInAnonymously() async {
    try {
      await _auth.signInAnonymously();
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  Future<Result<void>> signOut() async {
    try {
      await _auth.signOut();
      return const Result.success(null);
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Returns the current user's shop, or `null` if they haven't created one yet
  /// (drives the redirect to profile setup on first login).
  Future<Result<Shop?>> fetchMyShop() async {
    final user = currentUser;
    if (user == null) return const Result.success(null);
    try {
      final row = await _client
          .from('shops')
          .select()
          .eq('owner_id', user.id)
          .limit(1)
          .maybeSingle();
      return Result.success(row == null ? null : Shop.fromMap(row));
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Creates the current user's shop on first login.
  Future<Result<Shop>> createShop({
    required String name,
    String? address,
    String? phone,
    String currency = 'BDT',
  }) async {
    final user = currentUser;
    if (user == null) {
      return const Result.failure(AuthFailure('You must be signed in.'));
    }
    try {
      final payload = Shop(
        id: '',
        ownerId: user.id,
        name: name,
        address: address,
        phone: phone,
        currency: currency,
      ).toInsert(ownerId: user.id);

      final row = await _client.from('shops').insert(payload).select().single();
      return Result.success(Shop.fromMap(row));
    } catch (e) {
      return Result.failure(_map(e));
    }
  }

  /// Converts SDK exceptions into a user-friendly [Failure]. Never leak raw
  /// Postgres/Auth strings to the UI beyond Supabase's own readable messages.
  Failure _map(Object e) {
    if (e is AuthException) return AuthFailure(e.message);
    if (e is PostgrestException) {
      return DatabaseFailure(
        e.message.isNotEmpty
            ? e.message
            : 'Could not complete the request. Please try again.',
      );
    }
    if (e is SocketException) {
      return const NetworkFailure('No internet connection. Please try again.');
    }
    return const UnexpectedFailure('Something went wrong. Please try again.');
  }
}

/// Provider exposing the [AuthRepository].
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

/// The current user's shop (or null if not yet created). Refetches whenever auth
/// state changes; the router reads this to gate the profile-setup step.
final myShopProvider = FutureProvider<Shop?>((ref) async {
  ref.watch(authStateChangesProvider);
  final repo = ref.watch(authRepositoryProvider);
  if (repo.currentUser == null) return null;
  final result = await repo.fetchMyShop();
  return result.when(success: (shop) => shop, failure: (f) => throw f);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Exposes the initialized Supabase client to the app.
///
/// `Supabase.initialize(...)` is called once in `main()` before `runApp`; this
/// provider simply hands the singleton client to repositories. Repositories are
/// the ONLY layer that may touch this client — widgets go through controllers.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Streams Supabase auth state changes (sign in / out / token refresh).
///
/// The router's redirect guard and the auth controller both watch this so the
/// UI reacts to session changes immediately.
final authStateChangesProvider = StreamProvider<AuthState>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client.auth.onAuthStateChange;
});

/// The current authenticated [User], or `null` when signed out.
final currentUserProvider = Provider<User?>((ref) {
  // Re-read whenever auth state changes.
  ref.watch(authStateChangesProvider);
  return ref.watch(supabaseClientProvider).auth.currentUser;
});

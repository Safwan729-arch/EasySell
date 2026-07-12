import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/entrance.dart';
import '../../../l10n/app_localizations.dart';
import '../data/last_email_store.dart';
import 'auth_controller.dart';

/// Email/password sign in + sign up, plus Google OAuth.
///
/// The router handles where to go after a successful session (dashboard, or
/// profile setup if no shop exists yet), so this screen only triggers actions.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _isSignUp = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _prefillLastEmail();
  }

  /// Pre-fill the email field with the last address used to sign in, so the user
  /// only has to type their password. Skips if they've already started typing.
  Future<void> _prefillLastEmail() async {
    final email = await ref.read(lastEmailStoreProvider).read();
    if (!mounted || email == null || _emailController.text.isNotEmpty) return;
    _emailController.text = email;
    // Email is filled in for them — jump straight to the password field.
    if (!_isSignUp) _passwordFocus.requestFocus();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(authControllerProvider.notifier);
    final email = _emailController.text;
    final password = _passwordController.text;
    if (_isSignUp) {
      controller.signUpWithEmail(
        email,
        password,
        fullName: _nameController.text,
      );
    } else {
      controller.signInWithEmail(email, password);
    }
  }

  String? _validateEmail(AppLocalizations l10n, String? value) {
    if (value == null || value.trim().isEmpty) return l10n.auth_emailRequired;
    if (!value.contains('@')) return l10n.auth_emailInvalid;
    return null;
  }

  String? _validatePassword(AppLocalizations l10n, String? value) {
    if (value == null || value.isEmpty) return l10n.auth_passwordRequired;
    if (value.length < 6) return l10n.auth_passwordMin;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(authControllerProvider);
    final isLoading = state.isLoading;

    // Surface failures as friendly snackbars (never raw errors).
    ref.listen<AsyncValue<void>>(authControllerProvider, (_, next) {
      if (next is AsyncError) {
        // The persistent offline banner already communicates no-internet, so we
        // skip the redundant snackbar for network failures.
        if (next.error is NetworkFailure) return;
        final message = switch (next.error) {
          Failure(:final message) => message,
          _ => l10n.common_somethingWrong,
        };
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Entrance(
                      index: 0,
                      child: Icon(
                        Icons.storefront,
                        size: 56,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Entrance(
                      index: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'AI Shopkeeper',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text(
                            _isSignUp
                                ? l10n.auth_createAccount
                                : l10n.auth_welcomeBack,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    if (_isSignUp) ...[
                      TextFormField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: l10n.auth_fullName,
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                        validator: (v) =>
                            _isSignUp && (v == null || v.trim().isEmpty)
                            ? l10n.auth_nameRequired
                            : null,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: l10n.auth_email,
                        prefixIcon: const Icon(Icons.email_outlined),
                      ),
                      validator: (v) => _validateEmail(l10n, v),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      focusNode: _passwordFocus,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: l10n.auth_password,
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure ? Icons.visibility_off : Icons.visibility,
                          ),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (v) => _validatePassword(l10n, v),
                    ),
                    const SizedBox(height: 24),
                    Entrance(
                      index: 2,
                      child: FilledButton(
                        onPressed: isLoading ? null : _submit,
                        child: isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_isSignUp ? l10n.auth_signUp : l10n.auth_signIn),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: isLoading
                          ? null
                          : () => ref
                                .read(authControllerProvider.notifier)
                                .signInWithGoogle(),
                      icon: const Icon(Icons.login),
                      label: Text(l10n.auth_continueGoogle),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: isLoading
                          ? null
                          : () => setState(() => _isSignUp = !_isSignUp),
                      child: Text(
                        _isSignUp ? l10n.auth_haveAccount : l10n.auth_noAccount,
                      ),
                    ),
                    // Dev-only shortcut: never shipped in release builds.
                    if (kDebugMode)
                      TextButton.icon(
                        onPressed: isLoading
                            ? null
                            : () => ref
                                  .read(authControllerProvider.notifier)
                                  .signInAsGuest(),
                        icon: const Icon(Icons.bolt),
                        label: const Text('Continue as guest (dev)'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

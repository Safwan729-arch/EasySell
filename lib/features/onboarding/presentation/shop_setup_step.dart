import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../auth/presentation/auth_controller.dart';
import '../domain/currency_option.dart';

/// Step 2 of onboarding: create the shop, rendered in the language chosen on
/// step 1. Includes the required default-currency picker (BDT default). On
/// success `createShop` flips `myShopProvider` and the router moves the user to
/// the dashboard — so this widget needs no explicit navigation.
class ShopSetupStep extends ConsumerStatefulWidget {
  const ShopSetupStep({super.key});

  @override
  ConsumerState<ShopSetupStep> createState() => _ShopSetupStepState();
}

class _ShopSetupStepState extends ConsumerState<ShopSetupStep> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  ShopCurrency _currency = ShopCurrency.bdt;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref
        .read(authControllerProvider.notifier)
        .createShop(
          name: _nameController.text,
          address: _addressController.text,
          phone: _phoneController.text,
          currency: _currency.code,
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final isLoading = ref.watch(authControllerProvider).isLoading;

    ref.listen<AsyncValue<void>>(authControllerProvider, (_, next) {
      if (next is AsyncError) {
        final message = switch (next.error) {
          Failure(:final message) => message,
          _ => l10n.common_somethingWrong,
        };
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
      }
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.profile_tellUs, style: theme.textTheme.titleMedium),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.profile_shopName,
                prefixIcon: const Icon(Icons.storefront_outlined),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? l10n.profile_shopNameRequired
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressController,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: l10n.profile_address,
                prefixIcon: const Icon(Icons.location_on_outlined),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: l10n.profile_phone,
                prefixIcon: const Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.onboarding_defaultCurrency,
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            SegmentedButton<ShopCurrency>(
              segments: [
                for (final c in ShopCurrency.values)
                  ButtonSegment(
                    value: c,
                    label: Text('${c.symbol} ${c.code}'),
                  ),
              ],
              selected: {_currency},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _currency = s.first),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: isLoading ? null : _submit,
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.profile_createShop),
            ),
          ],
        ),
      ),
    );
  }
}

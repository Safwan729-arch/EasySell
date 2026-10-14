import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/haptics.dart';
import '../../../core/config/motion.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/cart_math.dart';
import 'cart_controller.dart';

/// Slim bar shown just above the bottom nav, on every tab, whenever the cart
/// has items. Tapping it opens the full Cart page.
class CartBar extends ConsumerWidget {
  const CartBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(cartControllerProvider);
    final theme = Theme.of(context);
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';

    return AnimatedSize(
      duration: AppMotion.fast,
      curve: AppMotion.easeOut,
      alignment: Alignment.topCenter,
      child: lines.isEmpty
          ? const SizedBox(width: double.infinity)
          : Material(
              color: theme.colorScheme.primary,
              child: InkWell(
                onTap: () {
                  AppHaptics.tap();
                  context.push('/cart');
                },
                child: SafeArea(
                  top: false,
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.shopping_cart,
                          color: theme.colorScheme.onPrimary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            context.l10n.cart_barSummary(
                              lines.length,
                              Money.format(cartTotal(lines), currencyCode: currency),
                            ),
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

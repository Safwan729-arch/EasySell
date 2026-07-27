import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/rounded_icon_tile.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/product.dart';
import 'inventory_controller.dart';

/// Lists products that have been archived (soft-deleted) and lets the shopkeeper
/// restore them to the active inventory. Reachable from Settings. Archiving keeps
/// a product's sales history intact, so nothing here is destructive.
class ArchivedProductsScreen extends ConsumerWidget {
  const ArchivedProductsScreen({super.key});

  Future<void> _restore(
    BuildContext context,
    WidgetRef ref,
    Product product,
  ) async {
    final ok = await ref
        .read(inventoryControllerProvider.notifier)
        .restore(product.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? context.l10n.inventory_restored(product.name)
                : context.l10n.inventory_couldNotRestore(product.name),
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archivedAsync = ref.watch(archivedProductsProvider);
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.settings_archivedProducts)),
      body: archivedAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(context.l10n.inventory_couldNotLoadArchived),
        ),
        data: (products) {
          if (products.isEmpty) return const _EmptyState();
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: products.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final p = products[i];
              final subtitle = [
                if (p.brand?.isNotEmpty ?? false) p.brand!,
                if (p.variant?.isNotEmpty ?? false) p.variant!,
              ].join(' · ');
              return ListTile(
                leading: RoundedTextTile(
                  text: p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                ),
                title: Text(p.name),
                subtitle: Text(
                  subtitle.isEmpty
                      ? Money.format(p.sellingPrice, currencyCode: currency)
                      : '$subtitle · '
                            '${Money.format(p.sellingPrice, currencyCode: currency)}',
                ),
                trailing: TextButton.icon(
                  onPressed: () => _restore(context, ref, p),
                  icon: const Icon(Icons.unarchive_outlined),
                  label: Text(context.l10n.common_restore),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(context.l10n.inventory_noArchived),
          const SizedBox(height: 4),
          Text(
            context.l10n.inventory_archivedHint,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

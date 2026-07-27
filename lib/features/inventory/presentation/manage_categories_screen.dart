import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../auth/data/auth_repository.dart';
import '../data/category_repository.dart';
import '../domain/category.dart';
import 'category_controller.dart';
import 'category_picker.dart';
import 'inventory_controller.dart';

/// Manage the shop's categories: see how many products use each, rename, add,
/// and delete. Deleting never removes products — it just uncategorizes them
/// (the ON DELETE SET NULL FK). Reachable from Settings.
class ManageCategoriesScreen extends ConsumerStatefulWidget {
  const ManageCategoriesScreen({super.key});

  @override
  ConsumerState<ManageCategoriesScreen> createState() =>
      _ManageCategoriesScreenState();
}

class _ManageCategoriesScreenState
    extends ConsumerState<ManageCategoriesScreen> {
  CategoryRepository get _repo => ref.read(categoryRepositoryProvider);

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _add() async {
    final l10n = context.l10n;
    final name = await promptCategoryName(context: context);
    if (name == null || name.trim().isEmpty) return;
    final shopId = ref.read(myShopProvider).value?.id;
    if (shopId == null) return _snack(l10n.category_noShop);

    final result = await _repo.upsertCategory(shopId: shopId, name: name);
    result.when(
      success: (_) => ref.invalidate(categoriesStreamProvider),
      failure: (f) => _snack(f.message),
    );
  }

  Future<void> _rename(Category category) async {
    final name = await promptCategoryName(
      context: context,
      initialValue: category.name,
      title: context.l10n.category_renameTitle,
      actionLabel: context.l10n.common_save,
    );
    if (name == null || name.trim().isEmpty || name.trim() == category.name) {
      return;
    }

    final result = await _repo.renameCategory(id: category.id, name: name);
    result.when(
      success: (_) => ref.invalidate(categoriesStreamProvider),
      failure: (f) => _snack(f.message),
    );
  }

  Future<void> _delete(Category category, int usageCount) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).extension<AppColors>()!;
        return AlertDialog(
          title: Text(ctx.l10n.category_deleteTitle),
          content: Text(
            usageCount == 0
                ? ctx.l10n.category_deleteBodyEmpty(category.name)
                : ctx.l10n.category_deleteBodyUsed(category.name, usageCount),
          ),
          // Natural-width actions: the theme forces FilledButton to a full-width
          // minimumSize, which otherwise makes "Delete" dwarf "Cancel".
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.l10n.common_cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                backgroundColor: colors.negative,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.l10n.common_delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final result = await _repo.deleteCategory(category.id);
    result.when(
      success: (_) {
        ref.invalidate(categoriesStreamProvider);
        // Refresh products so their now-null category and any filters update.
        ref.invalidate(productsStreamProvider);
      },
      failure: (f) => _snack(f.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesStreamProvider);
    final products = ref.watch(productsStreamProvider).value ?? const [];

    // Usage counts computed live from the product stream.
    final counts = <String, int>{};
    for (final p in products) {
      final id = p.categoryId;
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.settings_manageCategories),
        actions: [
          IconButton(
            tooltip: context.l10n.category_addTooltip,
            icon: const Icon(Icons.add),
            onPressed: _add,
          ),
        ],
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: Text(context.l10n.category_couldNotLoad),
        ),
        data: (categories) {
          if (categories.isEmpty) {
            return const _EmptyState();
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: categories.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final c = categories[i];
              final count = counts[c.id] ?? 0;
              return ListTile(
                title: Text(c.name),
                subtitle: Text(context.l10n.category_productCount(count)),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'rename') {
                      _rename(c);
                    } else if (action == 'delete') {
                      _delete(c, count);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'rename', child: Text(context.l10n.common_rename)),
                    PopupMenuItem(value: 'delete', child: Text(context.l10n.common_delete)),
                  ],
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
            Icons.category_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(context.l10n.category_noneYet),
          const SizedBox(height: 4),
          Text(
            context.l10n.category_tapToAdd,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

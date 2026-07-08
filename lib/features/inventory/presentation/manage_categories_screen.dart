import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/theme.dart';
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
    final name = await promptCategoryName(context: context);
    if (name == null || name.trim().isEmpty) return;
    final shopId = ref.read(myShopProvider).value?.id;
    if (shopId == null) return _snack('No shop found for this account.');

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
      title: 'Rename category',
      actionLabel: 'Save',
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
          title: const Text('Delete category?'),
          content: Text(
            usageCount == 0
                ? '"${category.name}" will be removed.'
                : '"${category.name}" will be removed. $usageCount '
                      '${usageCount == 1 ? 'product' : 'products'} will become '
                      'uncategorized (not deleted).',
          ),
          // Natural-width actions: the theme forces FilledButton to a full-width
          // minimumSize, which otherwise makes "Delete" dwarf "Cancel".
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 44),
                backgroundColor: colors.negative,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete'),
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
        title: const Text('Manage categories'),
        actions: [
          IconButton(
            tooltip: 'Add category',
            icon: const Icon(Icons.add),
            onPressed: _add,
          ),
        ],
      ),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(
          child: Text('Could not load categories. Pull to retry.'),
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
                subtitle: Text('$count ${count == 1 ? 'product' : 'products'}'),
                trailing: PopupMenuButton<String>(
                  onSelected: (action) {
                    if (action == 'rename') {
                      _rename(c);
                    } else if (action == 'delete') {
                      _delete(c, count);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
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
          const Text('No categories yet.'),
          const SizedBox(height: 4),
          Text(
            'Tap + to add one.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

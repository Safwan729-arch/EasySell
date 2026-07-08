import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../data/category_repository.dart';
import '../domain/category.dart';
import 'category_controller.dart';

/// Category dropdown for the product form, with an inline "+ Add new category"
/// action. Adding opens a small sheet (the form keeps its other fields), calls
/// the dedup-safe `upsert_category` RPC, then auto-selects the returned row —
/// noting gently when an equivalent category already existed.
class CategoryField extends ConsumerStatefulWidget {
  const CategoryField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  ConsumerState<CategoryField> createState() => _CategoryFieldState();
}

class _CategoryFieldState extends ConsumerState<CategoryField> {
  /// Sentinel for the "+ Add new category" entry (distinct from null = none).
  static const _addSentinel = '__add_new_category__';

  /// A just-added category, merged into the items until the realtime stream
  /// catches up — so the dropdown's selected value always matches an item.
  Category? _pending;
  String? _note;

  /// Bumped to rebuild the dropdown fresh from [widget.value]. Needed because
  /// the field seeds its display from `initialValue` only; this keeps the shown
  /// selection in sync after an inline add and reverts the transient "+ Add"
  /// selection if the user cancels.
  int _rev = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories =
        ref.watch(categoriesStreamProvider).value ?? const <Category>[];

    // Merge in a pending add not yet present in the stream snapshot.
    final merged = [...categories];
    final pending = _pending;
    if (pending != null && !merged.any((c) => c.id == pending.id)) {
      merged
        ..add(pending)
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String?>(
            key: ValueKey(_rev),
            initialValue: widget.value,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('No category'),
              ),
              for (final c in merged)
                DropdownMenuItem<String?>(value: c.id, child: Text(c.name)),
              DropdownMenuItem<String?>(
                value: _addSentinel,
                child: Row(
                  children: [
                    Icon(Icons.add, size: 16, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Add new category',
                      style: TextStyle(color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
            ],
            onChanged: (v) {
              if (v == _addSentinel) {
                // Revert the transient sentinel selection, then open the sheet.
                setState(() => _rev++);
                _startAdd();
              } else {
                setState(() {
                  _note = null;
                  _rev++;
                });
                widget.onChanged(v);
              }
            },
          ),
          if (_note != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Text(
                _note!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _startAdd() async {
    final name = await promptCategoryName(context: context);
    if (name == null || name.trim().isEmpty) return;

    final shopId = ref.read(myShopProvider).value?.id;
    if (shopId == null) {
      _snack('No shop found for this account.');
      return;
    }

    // Capture the ids we already had, to detect a dedup hit.
    final existingIds = (ref.read(categoriesStreamProvider).value ?? [])
        .map((c) => c.id)
        .toSet();

    final result = await ref
        .read(categoryRepositoryProvider)
        .upsertCategory(shopId: shopId, name: name);

    result.when(
      success: (category) {
        final alreadyExisted = existingIds.contains(category.id);
        // Refresh the list, then auto-select the new/returned category.
        ref.invalidate(categoriesStreamProvider);
        if (!mounted) return;
        setState(() {
          _pending = category;
          _note = alreadyExisted
              ? 'Already exists — selected it for you'
              : null;
          _rev++;
        });
        widget.onChanged(category.id);
      },
      failure: (f) => _snack(f.message),
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Bottom sheet that collects a category name (used for inline add and for
/// renaming on the Manage Categories screen). Returns the trimmed name, or null
/// if cancelled. The form/screen behind it keeps its state — this is a modal.
Future<String?> promptCategoryName({
  required BuildContext context,
  String? initialValue,
  String title = 'New category',
  String actionLabel = 'Add',
}) {
  final controller = TextEditingController(text: initialValue ?? '');
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      void submit() => Navigator.of(sheetContext).pop(controller.text.trim());
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 4,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(sheetContext).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => submit(),
              decoration: const InputDecoration(
                labelText: 'Category name',
                hintText: 'e.g. Frozen items',
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(sheetContext).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: submit,
                    child: Text(actionLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

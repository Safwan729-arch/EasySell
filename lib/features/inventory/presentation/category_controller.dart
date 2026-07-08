import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../data/category_repository.dart';
import '../domain/category.dart';
import 'inventory_controller.dart';

/// Live, name-ordered list of the current shop's categories (Supabase Realtime).
/// The product-form picker and the manage-categories screen watch this; inline
/// adds/renames/deletes reflect automatically.
final categoriesStreamProvider = StreamProvider.autoDispose<List<Category>>((
  ref,
) {
  final shop = ref.watch(myShopProvider).value;
  if (shop == null) return Stream.value(const <Category>[]);
  return ref.watch(categoryRepositoryProvider).watchCategories(shop.id);
});

/// Categories that currently have at least one product, name-ordered. Drives the
/// inventory list's filter chips so only in-use categories are offered.
final usedCategoriesProvider = Provider.autoDispose<List<Category>>((ref) {
  final categories = ref.watch(categoriesStreamProvider).value ?? const [];
  final products = ref.watch(productsStreamProvider).value ?? const [];
  final usedIds = <String>{
    for (final p in products)
      if (p.categoryId != null) p.categoryId!,
  };
  return categories.where((c) => usedIds.contains(c.id)).toList();
});

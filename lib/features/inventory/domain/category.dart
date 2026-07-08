import 'package:freezed_annotation/freezed_annotation.dart';

part 'category.freezed.dart';
part 'category.g.dart';

/// A shop-scoped, reusable product category. `nameNormalized` (lower-cased,
/// whitespace-collapsed) is what the DB deduplicates on via the
/// `unique (shop_id, name_normalized)` constraint; the app shows `name`.
@freezed
abstract class Category with _$Category {
  const Category._();

  const factory Category({
    required String id,
    required String shopId,
    required String name,
    required String nameNormalized,
    DateTime? createdAt,
  }) = _Category;

  factory Category.fromJson(Map<String, dynamic> json) =>
      _$CategoryFromJson(json);
}

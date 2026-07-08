import '../../inventory/domain/product.dart';

/// Turns the shop's products into the compact candidate list sent to the vision
/// model. Only id/name are guaranteed; brand/variant are included when present
/// (they sharpen label matching). Loose items simply carry no brand/variant.
List<Map<String, dynamic>> buildCandidates(List<Product> products) => [
  for (final p in products)
    {
      'id': p.id,
      'name': p.name,
      if (p.brand != null && p.brand!.isNotEmpty) 'brand': p.brand,
      if (p.variant != null && p.variant!.isNotEmpty) 'variant': p.variant,
    },
];

import '../../inventory/domain/product.dart';

/// Turns the shop's products into the compact candidate list sent to a model.
/// Only id/name are guaranteed; brand/variant are included when present (they
/// sharpen matching). Loose items simply carry no brand/variant.
///
/// [includeUnit] is opt-in so the vision-scan payload stays byte-for-byte
/// unchanged; the voice flow enables it because spoken sizes ("1 litre") match
/// far better when the model can see each product's unit.
List<Map<String, dynamic>> buildCandidates(
  List<Product> products, {
  bool includeUnit = false,
}) => [
  for (final p in products)
    {
      'id': p.id,
      'name': p.name,
      if (p.brand != null && p.brand!.isNotEmpty) 'brand': p.brand,
      if (p.variant != null && p.variant!.isNotEmpty) 'variant': p.variant,
      if (includeUnit) 'unit': p.unit.name,
    },
];

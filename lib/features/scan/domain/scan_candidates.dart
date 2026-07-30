import '../../inventory/domain/product.dart';

/// Turns the shop's products into the compact candidate list sent to a model.
/// Only id/name are guaranteed; brand/variant are included when present (they
/// sharpen matching). Loose items simply carry no brand/variant.
///
/// [includeUnit] is opt-in so the vision-scan payload stays byte-for-byte
/// unchanged; the voice flow enables it because spoken sizes ("1 litre") match
/// far better when the model can see each product's unit.
///
/// [recentUnits] optionally supplies units-sold-recently per product id (see
/// `recentUnitsSoldProvider`). Products with a positive count carry a `recent`
/// field the model can use to break a tie the speech left open; products with
/// no recent sales carry nothing, so the payload does not grow for a shop that
/// has just started. Omitting the argument leaves every payload byte-for-byte
/// as it was.
List<Map<String, dynamic>> buildCandidates(
  List<Product> products, {
  bool includeUnit = false,
  Map<String, double>? recentUnits,
}) => [
  for (final p in products)
    {
      'id': p.id,
      'name': p.name,
      if (p.brand != null && p.brand!.isNotEmpty) 'brand': p.brand,
      if (p.variant != null && p.variant!.isNotEmpty) 'variant': p.variant,
      if (includeUnit) 'unit': p.unit.name,
      // Rounded: the model only needs the order of magnitude to rank, and
      // whole numbers keep the prompt compact. Tested on the rounded value so
      // a fractional trickle (0.4 kg in a month) never emits a bare `recent: 0`
      // that reads as a real signal.
      if ((recentUnits?[p.id] ?? 0).round() > 0)
        'recent': recentUnits![p.id]!.round(),
    },
];

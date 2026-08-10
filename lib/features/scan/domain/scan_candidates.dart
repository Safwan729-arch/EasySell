import '../../inventory/domain/product.dart';

/// The candidate list sent to a model, plus the mapping needed to turn the
/// identifier the model echoes back into a real product id.
///
/// Candidates are keyed by **list index**, not product uuid. The catalog is
/// re-sent inside the prompt on every single scan (see the Edge Function's
/// `instruction()`), so at ~100 products it is roughly 90% of the request --
/// and a 36-char uuid costs ~20 tokens per candidate while carrying no meaning
/// the model can use. It only has to echo an identifier back; a small integer
/// does that job for a fraction of the tokens.
class CandidatePayload {
  const CandidatePayload({required this.candidates, required this._productIds});

  final List<Map<String, dynamic>> candidates;
  final List<String> _productIds;

  /// Resolves the identifier a model returned back to the shop's product id.
  /// Null for anything the model invented -- out of range, negative, or not a
  /// number at all -- so a hallucinated id can never land on a real product.
  String? resolve(String returned) {
    final i = int.tryParse(returned);
    if (i == null || i < 0 || i >= _productIds.length) return null;
    return _productIds[i];
  }
}

/// Builds the compact candidate list. Only index/name are guaranteed;
/// brand/variant are included when present (they sharpen matching). Loose items
/// simply carry no brand/variant.
///
/// [includeUnit] is opt-in: the voice flow enables it because spoken sizes
/// ("1 litre") match far better when the model can see each product's unit.
///
/// [recentUnits] optionally supplies units-sold-recently **keyed by product
/// id** (see `recentUnitsSoldProvider`). Products with a positive count carry a
/// `recent` field the model can use to break a tie the speech left open, so the
/// payload does not grow for a shop that has just started.
CandidatePayload buildCandidatePayload(
  List<Product> products, {
  bool includeUnit = false,
  Map<String, double>? recentUnits,
}) {
  final candidates = <Map<String, dynamic>>[];
  final productIds = <String>[];
  for (var i = 0; i < products.length; i++) {
    final p = products[i];
    candidates.add({
      'i': i,
      'name': p.name,
      if (p.brand != null && p.brand!.isNotEmpty) 'brand': p.brand,
      if (p.variant != null && p.variant!.isNotEmpty) 'variant': p.variant,
      if (includeUnit) 'unit': p.unit.name,
      // Rounded: the model only needs the order of magnitude to rank, and whole
      // numbers keep the prompt compact. Tested on the rounded value so a
      // fractional trickle (0.4 kg in a month) never emits a bare `recent: 0`
      // that reads as a real signal.
      if ((recentUnits?[p.id] ?? 0).round() > 0)
        'recent': recentUnits![p.id]!.round(),
    });
    productIds.add(p.id);
  }
  return CandidatePayload(candidates: candidates, productIds: productIds);
}

// Kept until Task 8 migrates the voice flow off uuid candidates.
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
      if ((recentUnits?[p.id] ?? 0).round() > 0)
        'recent': recentUnits![p.id]!.round(),
    },
];

// The parsed outcome of a `parse-sale` request. Plain Dart (no codegen) so the
// JSON handling is small, explicit, and directly unit-testable -- same choice as
// the vision scan's RecognitionResult.

/// One candidate product the model matched, by the shop's own product id.
class VoiceMatch {
  const VoiceMatch({required this.productId, required this.confidence});

  final String productId;
  final double confidence;

  factory VoiceMatch.fromJson(Map<String, dynamic> json) => VoiceMatch(
    productId: json['product_id'] as String,
    confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
  );
}

/// One spoken item: what was heard, how many, and which products it might be.
class VoiceItem {
  const VoiceItem({
    required this.heard,
    required this.quantity,
    required this.quantityAssumed,
    this.unitHeard,
    this.matches = const <VoiceMatch>[],
  });

  /// The fragment of speech this line came from, e.g. "pepsi 1 litre". Size
  /// words live HERE (they identify the product); counts live in [quantity].
  final String heard;

  /// How many units. Never carries a size -- see [heard].
  final double quantity;

  /// True when the speaker gave no count and we defaulted to 1. The review UI
  /// highlights these so an assumed number is never mistaken for a heard one.
  final bool quantityAssumed;

  /// A spoken count word ("piece", "packet", "টা"), when present. Advisory only.
  final String? unitHeard;

  /// Ranked candidates, highest confidence first.
  final List<VoiceMatch> matches;

  factory VoiceItem.fromJson(Map<String, dynamic> json) {
    final rawQty = json['quantity'];
    final qty = rawQty is num ? rawQty.toDouble() : null;
    final valid = qty != null && qty > 0;
    final rawMatches = (json['matches'] as List?) ?? const [];
    return VoiceItem(
      heard: (json['heard'] as String?) ?? '',
      quantity: valid ? qty : 1,
      quantityAssumed: !valid,
      unitHeard: json['unit_heard'] as String?,
      matches: [
        for (final m in rawMatches)
          VoiceMatch.fromJson(Map<String, dynamic>.from(m as Map)),
      ],
    );
  }
}

/// Normalized result returned by the `parse-sale` Edge Function.
class VoiceParseResult {
  const VoiceParseResult({this.heardText, this.items = const <VoiceItem>[]});

  /// The full transcript, shown to the user so a mishear is obvious.
  final String? heardText;
  final List<VoiceItem> items;

  factory VoiceParseResult.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] as List?) ?? const [];
    return VoiceParseResult(
      heardText: json['heard_text'] as String?,
      items: [
        for (final i in rawItems)
          VoiceItem.fromJson(Map<String, dynamic>.from(i as Map)),
      ],
    );
  }
}

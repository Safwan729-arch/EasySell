import 'voice_decision.dart';
import 'voice_parse_result.dart';

/// One row in the review sheet: what was heard, how many, and which product it
/// resolves to. Immutable -- edits return a new instance.
class VoiceLine {
  const VoiceLine({
    required this.heard,
    required this.quantity,
    required this.quantityAssumed,
    required this.status,
    required this.choices,
    this.chosenProductId,
  });

  final String heard;
  final double quantity;

  /// True when no count was spoken and we defaulted to 1; the UI highlights it.
  final bool quantityAssumed;

  final VoiceLineStatus status;

  /// Candidates to offer when the user must choose.
  final List<VoiceMatch> choices;

  /// The product this line will add to the cart. Null until settled.
  final String? chosenProductId;

  /// A line may only reach the cart once a real product is attached.
  bool get isSettled => chosenProductId != null;

  VoiceLine chooseProduct(String productId) =>
      _copy(chosenProductId: productId);

  VoiceLine withQuantity(double newQuantity) => _copy(quantity: newQuantity);

  VoiceLine _copy({String? chosenProductId, double? quantity}) => VoiceLine(
    heard: heard,
    quantity: quantity ?? this.quantity,
    quantityAssumed: quantityAssumed,
    status: status,
    choices: choices,
    chosenProductId: chosenProductId ?? this.chosenProductId,
  );
}

/// Turn a parsed result into reviewable lines, pre-choosing only clear winners.
List<VoiceLine> buildVoiceLines(
  VoiceParseResult result, {
  VoiceThresholds thresholds = const VoiceThresholds(),
}) => [
  for (final item in result.items)
    () {
      final d = decideVoiceLine(item.matches, thresholds: thresholds);
      return VoiceLine(
        heard: item.heard,
        quantity: item.quantity,
        quantityAssumed: item.quantityAssumed,
        status: d.status,
        choices: d.choices,
        // Only a clear winner is pre-filled. Ambiguous and notFound stay null
        // so the user is forced to settle them.
        chosenProductId: d.status == VoiceLineStatus.resolved
            ? d.choices.single.productId
            : null,
      );
    }(),
];

/// Drop a line the user gave up on (e.g. an item they don't stock).
List<VoiceLine> removeLineAt(List<VoiceLine> lines, int index) =>
    [...lines]..removeAt(index);

/// The gate: nothing reaches the cart until every line has a real product.
bool canAddToCart(List<VoiceLine> lines) =>
    lines.isNotEmpty && lines.every((l) => l.isSettled);

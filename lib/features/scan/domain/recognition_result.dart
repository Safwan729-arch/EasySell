// The outcome of a vision recognition request. Plain Dart (no codegen) so the
// JSON parsing is small, explicit, and directly unit-testable.

enum RecognitionStatus { match, multiple, none }

/// One candidate the model matched, by the shop's own product id.
class ProductMatch {
  const ProductMatch({required this.productId, required this.confidence});

  final String productId;
  final double confidence;

  factory ProductMatch.fromJson(Map<String, dynamic> json) => ProductMatch(
    productId: json['product_id'] as String,
    confidence: (json['confidence'] as num).toDouble(),
  );
}

/// Normalized result returned by the `recognize-product` Edge Function.
class RecognitionResult {
  const RecognitionResult({
    required this.status,
    this.matches = const <ProductMatch>[],
    this.readBrand,
    this.readName,
    this.readSize,
  });

  final RecognitionStatus status;
  final List<ProductMatch> matches;
  final String? readBrand;
  final String? readName;
  final String? readSize;

  factory RecognitionResult.fromJson(Map<String, dynamic> json) {
    final rawMatches = (json['matches'] as List?) ?? const [];
    return RecognitionResult(
      status: _statusFrom(json['status']),
      matches: [
        for (final m in rawMatches)
          ProductMatch.fromJson(Map<String, dynamic>.from(m as Map)),
      ],
      readBrand: json['read_brand'] as String?,
      readName: json['read_name'] as String?,
      readSize: json['read_size'] as String?,
    );
  }

  static RecognitionStatus _statusFrom(Object? raw) => switch (raw) {
    'match' => RecognitionStatus.match,
    'multiple' => RecognitionStatus.multiple,
    _ => RecognitionStatus.none,
  };
}

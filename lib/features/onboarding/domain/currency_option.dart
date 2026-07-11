/// The currencies a shop can be created with, in display order (BDT first =
/// the pre-selected default). Symbols are the literal glyphs the app shows on
/// money elsewhere (matching `Money.format`), hardcoded here so the picker never
/// depends on locale-specific currency-symbol resolution (e.g. "US\$").
enum ShopCurrency {
  bdt('BDT', '৳'),
  usd('USD', '\$');

  const ShopCurrency(this.code, this.symbol);

  /// ISO code stored in `shops.currency` (e.g. 'BDT').
  final String code;

  /// Display glyph (৳ / \$).
  final String symbol;

  /// Resolves a stored code back to an option; unknown codes fall back to the
  /// BDT default so a bad/legacy value never crashes the picker.
  static ShopCurrency fromCode(String code) =>
      values.firstWhere((c) => c.code == code, orElse: () => ShopCurrency.bdt);
}

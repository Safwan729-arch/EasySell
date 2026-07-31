import 'package:intl/intl.dart';

/// Quantity/count formatting: drops a trailing ".0" and any trailing zeros so
/// counts read cleanly ("12", "2.5") whatever the unit. The single home for
/// this — [Money] handles currency, [Qty] handles bare counts. [Product.trimNum]
/// delegates here, as do the quantity steppers and stat rows.
class Qty {
  const Qty._();

  static String format(num v) {
    final d = v.toDouble();
    // NumberFormat localizes digits + grouping via Intl.defaultLocale, so
    // counts render in Bengali digits (০-৯) when the app is in Bengali.
    return d == d.roundToDouble()
        ? NumberFormat.decimalPattern().format(d)
        : NumberFormat('#,##0.###').format(d);
  }
}

/// Percentage formatting: one decimal place, with a trailing ".0" dropped so
/// 14.0 reads "14%" but 8.2 stays "8.2%". The single home for this — the margin
/// stat, the breakdown sheet and both delta indicators all route through here.
///
/// Goes through [NumberFormat] rather than `toStringAsFixed` so the digits
/// follow `Intl.defaultLocale`. `%` is kept as-is: it is the percent sign the
/// bn locale itself specifies, not an English character.
class Pct {
  const Pct._();

  static String format(num percent) {
    // Round to the displayed precision *before* asking whether the value is
    // whole, so 14.04 reads "14%" and not "14.0%" — matching the hand-rolled
    // `toStringAsFixed(1)` + trim-".0" this replaced.
    final rounded = (percent.toDouble() * 10).round() / 10;
    final pattern = rounded == rounded.roundToDouble() ? '#,##0' : '#,##0.0';
    return '${NumberFormat(pattern).format(rounded)}%';
  }
}

/// Money/number formatting helpers shared across screens.
class Money {
  const Money._();

  /// Formats [amount] using the shop's [currencyCode] (e.g. 'USD', 'INR').
  /// Falls back to a plain number if the code is unknown to intl.
  static String format(num amount, {String currencyCode = 'USD'}) {
    try {
      return NumberFormat.simpleCurrency(name: currencyCode).format(amount);
    } catch (_) {
      // Still via NumberFormat: an unknown currency code must not also cost the
      // user their own digits.
      return '${NumberFormat('#,##0.00').format(amount)} $currencyCode';
    }
  }

  /// "Conservative" compact currency for dashboard stat cards. Full digits (no
  /// cents) below 100,000; `K` from 100K; `M` from 1,000,000 (2 dp, 1 dp ≥ 10M).
  /// Keeps everyday till figures exact and only abbreviates large totals — the
  /// tap-to-expand breakdown sheet provides full precision when needed.
  static String compact(num amount, {String currencyCode = 'USD'}) {
    final abs = amount.abs();
    if (abs < 100000) {
      try {
        return NumberFormat.simpleCurrency(
          name: currencyCode,
          decimalDigits: 0,
        ).format(amount);
      } catch (_) {
        return '${NumberFormat('#,##0').format(amount.round())} $currencyCode';
      }
    }
    String symbol;
    try {
      symbol = NumberFormat.simpleCurrency(name: currencyCode).currencySymbol;
    } catch (_) {
      symbol = '$currencyCode ';
    }
    return '${amount < 0 ? '-' : ''}$symbol${_compactMagnitude(abs)}';
  }

  /// Compact integer counts (e.g. units sold) with the same 100,000 threshold.
  static String compactCount(num count) {
    final abs = count.abs();
    if (abs < 100000) return NumberFormat.decimalPattern().format(count);
    return '${count < 0 ? '-' : ''}${_compactMagnitude(abs)}';
  }

  /// Whether to abbreviate on the Indian scale (লাখ / কোটি) instead of the
  /// Western one (K / M).
  ///
  /// The app ships English and Bengali only (`supportedAppLocales`). A hard-coded
  /// `K` was wrong for Bengali twice over: it is an English letter, and it is the
  /// wrong unit — the bn locale already groups full figures in lakh style
  /// (১,১৩,৩৩৫), so a shopkeeper reading "121K" gets a magnitude that matches
  /// neither their language nor the number printed directly beneath it.
  ///
  /// Branching on the locale inside a formatter follows the precedent set by
  /// `weekdayBarLabel`, and for the same reason: the correct output is not a
  /// translation of the English one.
  static bool get _indicScale => Intl.getCurrentLocale().startsWith('bn');

  /// Shared magnitude suffix for a non-negative value ≥ 100,000. English:
  /// `452K`, `1.28M`, `19.3M`. Bengali: `৪.৫২ লাখ`, `১.৯৩ কোটি`.
  ///
  /// Both scales share the 100,000 threshold because it is exactly 1 লাখ, and
  /// both roll up when the rounded display would overflow its own unit (`999.6K`
  /// → `1.00M`, `99.99 লাখ` → `১.০০ কোটি`).
  static String _compactMagnitude(num abs) {
    if (_indicScale) {
      final lakh = abs / 100000;
      // Test the *rounded* value: 9,999,900 displays as "100.0 লাখ" otherwise.
      if (_displayRound(lakh) < 100) return '${_scaled(lakh)} লাখ';
      return '${_scaled(abs / 10000000)} কোটি';
    }
    final k = (abs / 1000).round();
    // NumberFormat, not '$k', so the digits follow Intl.defaultLocale.
    if (k < 1000) return '${NumberFormat('#,##0').format(k)}K';
    return '${_scaled(abs / 1000000)}M';
  }

  /// Two decimals below 10, one at/above — keeps the abbreviation about the same
  /// width at every magnitude. Localizes its digits.
  static String _scaled(double v) =>
      NumberFormat(v >= 10 ? '#,##0.0' : '#,##0.00').format(v);

  /// The value [_scaled] will actually show, for roll-up comparisons.
  static double _displayRound(double v) {
    final f = v >= 10 ? 10 : 100;
    return (v * f).round() / f;
  }
}

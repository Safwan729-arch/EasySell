import 'package:intl/intl.dart';

/// Money/number formatting helpers shared across screens.
class Money {
  const Money._();

  /// Formats [amount] using the shop's [currencyCode] (e.g. 'USD', 'INR').
  /// Falls back to a plain number if the code is unknown to intl.
  static String format(num amount, {String currencyCode = 'USD'}) {
    try {
      return NumberFormat.simpleCurrency(name: currencyCode).format(amount);
    } catch (_) {
      return '${amount.toStringAsFixed(2)} $currencyCode';
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
        return '${amount.round()} $currencyCode';
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

  /// Shared magnitude suffix for a non-negative value ≥ 100,000: `452K`,
  /// `1.28M`, `19.3M`. A `K` value that rounds to 1000 rolls up to `1.00M`.
  static String _compactMagnitude(num abs) {
    final k = (abs / 1000).round();
    if (k < 1000) return '${k}K';
    final m = abs / 1000000;
    return '${m.toStringAsFixed(m >= 10 ? 1 : 2)}M';
  }
}

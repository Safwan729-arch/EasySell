import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/l10n/failure_text.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/l10n/app_localizations_bn.dart';
import 'package:ai_shopkeeper/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

/// Our Postgres functions `raise exception` with English sentences. Passing
/// those to a snackbar left a Bengali-first app showing English at the exact
/// moment a sale failed — and CLAUDE.md §6 forbids surfacing raw Postgres text
/// at all. Repositories now classify into a [Failure.code] and the UI
/// translates it.
///
/// The strings on the left of each case are the migrations' ACTUAL text. If a
/// migration's wording changes without the matcher changing with it, these
/// tests fail — rather than the app silently falling back to English.

void main() {
  _classification();

  final en = AppLocalizationsEn();
  final bn = AppLocalizationsBn();

  test('a coded failure renders in Bengali, not the server\'s English', () {
    const f = DatabaseFailure(
      'Insufficient stock for Pepsi: have 3, need 5',
      code: ServerErrorCodes.insufficientStock,
      detail: 'Pepsi',
    );
    final text = failureText(bn, f);
    expect(text.contains('Pepsi'), isTrue, reason: 'the product must survive');
    expect(
      text.contains('Insufficient'),
      isFalse,
      reason: 'the raw server sentence must not reach the shopkeeper',
    );
    expect(text, bn.error_insufficientStock('Pepsi'));
  });

  test('every code has a translation in both locales', () {
    const codes = [
      ServerErrorCodes.insufficientStock,
      ServerErrorCodes.cartEmpty,
      ServerErrorCodes.productNotFound,
      ServerErrorCodes.customerNotFound,
      ServerErrorCodes.discountExceedsTotal,
      ServerErrorCodes.discountNegative,
      ServerErrorCodes.quantityNotPositive,
      ServerErrorCodes.expiredStockInCart,
      ServerErrorCodes.batchShortInCart,
      ServerErrorCodes.batchNotAvailable,
    ];
    for (final code in codes) {
      for (final AppLocalizations l10n in [en, bn]) {
        final text = failureText(
          l10n,
          DatabaseFailure('RAW SERVER TEXT', code: code, detail: 'X'),
        );
        expect(
          text,
          isNot('RAW SERVER TEXT'),
          reason: '$code fell through to the English fallback',
        );
        expect(text.trim(), isNotEmpty);
      }
    }
  });

  test('an unclassified failure still says something specific', () {
    // The fallback is English, deliberately: a vague localised shrug would be
    // worse than a precise sentence the shopkeeper can act on or report.
    const f = DatabaseFailure('some unmapped postgres complaint');
    expect(failureText(en, f), 'some unmapped postgres complaint');
  });
}

/// Pins the classifier against the EXACT strings the migrations raise. Copy
/// them from `supabase/migrations/` when they change — that is the point of
/// this group: a reworded migration should fail here rather than quietly drop
/// the app back to English.
void _classification() {
  group('classifyServerMessage', () {
    test('0001/0009: insufficient stock, product name recovered', () {
      final r = classifyServerMessage(
        'Insufficient stock for Soyabean Oil: have 3.000, need 5.000',
      );
      expect(r.code, ServerErrorCodes.insufficientStock);
      expect(r.detail, 'Soyabean Oil');
    });

    test('a product name containing a colon still resolves', () {
      final r = classifyServerMessage(
        'Insufficient stock for Pepsi: 500ml: have 1.000, need 2.000',
      );
      expect(r.code, ServerErrorCodes.insufficientStock);
      expect(
        r.detail,
        'Pepsi: 500ml',
        reason: 'the match must be anchored on ": have ", not the first colon',
      );
    });

    test('0009: discount exceeds total', () {
      final r = classifyServerMessage(
        'Discount exceeds total: most you can take off is 122.54, asked for 122.545',
      );
      expect(r.code, ServerErrorCodes.discountExceedsTotal);
    });

    test('0009: negative discount', () {
      expect(
        classifyServerMessage('Discount cannot be negative').code,
        ServerErrorCodes.discountNegative,
      );
    });

    test('0007: empty cart', () {
      expect(
        classifyServerMessage('Cart is empty').code,
        ServerErrorCodes.cartEmpty,
      );
    });

    test('0007: bad quantity', () {
      expect(
        classifyServerMessage('Quantity must be greater than zero').code,
        ServerErrorCodes.quantityNotPositive,
      );
    });

    test('0012: a picked delivery the server refuses', () {
      expect(
        classifyServerMessage('Batch not available').code,
        ServerErrorCodes.batchNotAvailable,
      );
    });

    test('0007/0008: missing rows', () {
      expect(
        classifyServerMessage('Product not found').code,
        ServerErrorCodes.productNotFound,
      );
      expect(
        classifyServerMessage('Customer not found').code,
        ServerErrorCodes.customerNotFound,
      );
    });

    test('anything unrecognised classifies as null, not a wrong code', () {
      final r = classifyServerMessage('duplicate key value violates ...');
      expect(r.code, isNull);
      expect(r.detail, isNull);
    });
  });
}

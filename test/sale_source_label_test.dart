import 'package:ai_shopkeeper/core/l10n/enum_labels.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/l10n/app_localizations_en.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final AppLocalizations l10n = AppLocalizationsEn();

  test('maps known sources to their localized labels', () {
    expect(saleSourceLabel(l10n, 'manual'), 'Manual');
    expect(saleSourceLabel(l10n, 'voice'), 'Voice');
    expect(saleSourceLabel(l10n, 'image'), 'Photo scan');
  });

  test('null and unknown sources fall back to an em dash', () {
    expect(saleSourceLabel(l10n, null), '—');
    expect(saleSourceLabel(l10n, 'something-else'), '—');
  });
}

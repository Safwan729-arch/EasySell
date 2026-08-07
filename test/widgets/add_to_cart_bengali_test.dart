import 'package:ai_shopkeeper/core/config/theme.dart';
import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/cart/presentation/add_to_cart_sheet.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// The add-to-cart quantity field used to write itself back through
/// `Qty.format`, which localises digits via `intl`. In Bengali that produced
/// `০.১২৩`, and the field is re-parsed with `double.tryParse` on every
/// keystroke — which cannot read Bengali numerals. So one snap-back left text
/// the next edit resolved to null, silently zeroing the quantity in the app's
/// PRIMARY locale.
///
/// `discount_sheet.dart` documents avoiding exactly this trap; this pins the
/// same rule for the older sheet.

const _rice = Product(
  id: 'p1',
  shopId: 's1',
  name: 'Rice',
  sellingPrice: 100,
  buyingPrice: 80,
  quantity: 50,
  unit: ProductUnit.kg,
);

Future<ProviderContainer> _container() async {
  final container = ProviderContainer(
    overrides: [
      myShopProvider.overrideWith(
        (ref) async =>
            const Shop(id: 's1', ownerId: 'o1', name: 'Shop', currency: 'BDT'),
      ),
    ],
  );
  addTearDown(container.dispose);
  await container.read(myShopProvider.future);
  return container;
}

Widget _app(ProviderContainer container, Locale locale) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        locale: locale,
        supportedLocales: supportedAppLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAddToCartSheet(context, product: _rice),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

Future<void> _open(WidgetTester tester, Locale locale) async {
  final c = await _container();
  await tester.pumpWidget(_app(c, locale));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('in Bengali the quantity field holds parseable ASCII', (
    tester,
  ) async {
    await _open(tester, const Locale('bn'));
    final text = _fieldText(tester);
    expect(
      double.tryParse(text),
      isNotNull,
      reason:
          'the field is re-parsed on every keystroke -- Bengali numerals '
          'would resolve to null and zero the quantity',
    );
    expect(RegExp(r'^[0-9.]+$').hasMatch(text), isTrue, reason: 'got "$text"');
  });

  testWidgets('a clamped entry snaps back to parseable text in Bengali', (
    tester,
  ) async {
    // The live path: typing over stock forces a snap-back, which is where the
    // localised digits used to get written into the field.
    await _open(tester, const Locale('bn'));
    await tester.enterText(find.byType(TextField), '999');
    await tester.pump();

    final text = _fieldText(tester);
    expect(double.tryParse(text), 50, reason: 'clamped to stock, still ASCII');
  });

  testWidgets('editing after a snap-back keeps the quantity', (tester) async {
    await _open(tester, const Locale('bn'));
    await tester.enterText(find.byType(TextField), '999');
    await tester.pump();
    // Second edit: previously the field now held ৫০, and this keystroke
    // re-parsed it to null and zeroed everything.
    await tester.enterText(find.byType(TextField), _fieldText(tester));
    await tester.pump();

    expect(double.tryParse(_fieldText(tester)), 50);
  });

  testWidgets('English is unchanged', (tester) async {
    await _open(tester, const Locale('en'));
    expect(double.tryParse(_fieldText(tester)), isNotNull);
  });
}

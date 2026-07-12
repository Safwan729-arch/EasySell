import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:ai_shopkeeper/core/widgets/offline_banner.dart';
import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:ai_shopkeeper/shared/providers/connectivity_provider.dart';

Widget _harness({required bool online}) {
  return ProviderScope(
    overrides: [
      isOnlineProvider.overrideWith((ref) => Stream.value(online)),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: OfflineBanner()),
    ),
  );
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('shows the no-internet text when offline', (tester) async {
    await tester.pumpWidget(_harness(online: false));
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsOneWidget);
  });

  testWidgets('renders nothing when online', (tester) async {
    await tester.pumpWidget(_harness(online: true));
    await tester.pumpAndSettle();
    expect(find.text('No internet connection'), findsNothing);
  });
}

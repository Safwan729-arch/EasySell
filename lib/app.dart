import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/theme.dart';
import 'core/router/app_router.dart';
import 'core/widgets/offline_banner.dart';
import 'l10n/app_localizations.dart';
import 'shared/providers/connectivity_provider.dart';
import 'shared/providers/locale_provider.dart';
import 'shared/providers/theme_mode_provider.dart';

/// Root widget: wires the Material 3 theme and the go_router config.
class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(goRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    return MaterialApp.router(
      title: 'AI Shopkeeper',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: supportedAppLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
      // Pin the OS font scale to 1.0 so the app always renders at its designed
      // (compact) sizes regardless of the device's "Font size / Display size"
      // setting — the most common reason text looked oversized on-device.
      builder: (context, child) {
        // Transparent system bars with icon brightness that follows the active
        // theme, so status/nav icons always contrast. Applies app-wide,
        // including the AppBar-less main tab screens.
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: isDark
                ? Brightness.light
                : Brightness.dark,
          ),
          child: MediaQuery.withClampedTextScaling(
            minScaleFactor: 1.0,
            maxScaleFactor: 1.0,
            child: Consumer(
              builder: (context, ref, _) {
                // While offline the banner sits above the routed screen and its
                // own SafeArea already consumes the status-bar inset, so strip
                // the top padding from the screen below it to avoid reserving
                // that gap twice. Scoped to this Consumer so only this subtree
                // rebuilds when connectivity flips.
                final isOnline = ref.watch(isOnlineProvider).value ?? true;
                return Column(
                  children: [
                    const OfflineBanner(),
                    Expanded(
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: !isOnline,
                        child: child!,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App-specific colors not covered by [ColorScheme] (deltas, muted surfaces).
/// Access via `Theme.of(context).extension<AppColors>()!`.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.positive,
    required this.negative,
    required this.warning,
    required this.muted,
    required this.navBar,
    required this.onNavBar,
    required this.heroOnAccent,
  });

  final Color positive; // green deltas / up trends
  final Color negative; // red deltas / down trends
  /// low-stock / caution
  final Color warning;
  final Color muted; // subtle pill / icon-tile backgrounds
  final Color navBar; // bottom nav background
  final Color onNavBar; // inactive icon color on the nav bar
  /// text/icon on a blue-filled accent card
  final Color heroOnAccent;

  @override
  AppColors copyWith({
    Color? positive,
    Color? negative,
    Color? warning,
    Color? muted,
    Color? navBar,
    Color? onNavBar,
    Color? heroOnAccent,
  }) => AppColors(
    positive: positive ?? this.positive,
    negative: negative ?? this.negative,
    warning: warning ?? this.warning,
    muted: muted ?? this.muted,
    navBar: navBar ?? this.navBar,
    onNavBar: onNavBar ?? this.onNavBar,
    heroOnAccent: heroOnAccent ?? this.heroOnAccent,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      positive: Color.lerp(positive, other.positive, t)!,
      negative: Color.lerp(negative, other.negative, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      navBar: Color.lerp(navBar, other.navBar, t)!,
      onNavBar: Color.lerp(onNavBar, other.onNavBar, t)!,
      heroOnAccent: Color.lerp(heroOnAccent, other.heroOnAccent, t)!,
    );
  }
}

/// Resolved color palette for one [Brightness]. Lets [AppTheme._build] stay a
/// single code path while light and dark each supply their own surface/ink set.
@immutable
class _Palette {
  const _Palette({
    required this.brightness,
    required this.brand,
    required this.onBrand,
    required this.positive,
    required this.negative,
    required this.warning,
    required this.bg,
    required this.card,
    required this.cardRaised,
    required this.border,
    required this.ink,
    required this.inkMuted,
    required this.navBar,
    required this.heroOnAccent,
  });

  final Brightness brightness;
  final Color brand; // accent
  final Color onBrand; // text/icon on a brand-filled surface
  final Color positive;
  final Color negative;
  final Color warning;
  final Color bg; // scaffold canvas
  final Color card; // base surface
  final Color cardRaised; // subtle tinted surface
  final Color border; // hairline border / divider
  final Color ink; // primary text
  final Color inkMuted; // secondary text
  final Color navBar; // bottom nav background
  final Color heroOnAccent; // text/icon on a blue-filled accent card
}

/// Material 3 theme with a royal-blue accent. Ships a light (soft gray-blue
/// canvas) and a dark (deep navy canvas) variant sharing one structural build.
class AppTheme {
  const AppTheme._();

  static const Color brand = Color(0xFF2563EB); // royal blue accent
  static const Color brandDeep = Color(0xFF1D4ED8); // pressed / deep

  static const _Palette _lightPalette = _Palette(
    brightness: Brightness.light,
    brand: brand,
    onBrand: Colors.white,
    positive: Color(0xFF16A34A), // profit / up = green
    negative: Color(0xFFDC2626),
    warning: Color(0xFFEA580C), // low-stock amber-orange
    bg: Color(0xFFEEF2F7), // soft gray-blue canvas
    card: Color(0xFFFFFFFF),
    cardRaised: Color(0xFFF1F4F8), // subtle tinted surfaces
    border: Color(0xFFE7EBF1), // hairline border / divider
    ink: Color(0xFF0F172A), // primary text
    inkMuted: Color(0xFF8A94A6), // secondary text
    navBar: Color(0xFFFFFFFF),
    heroOnAccent: Colors.white,
  );

  static const _Palette _darkPalette = _Palette(
    brightness: Brightness.dark,
    brand: Color(0xFF5B9CFF), // brighter royal blue for contrast on navy
    onBrand: Color(0xFF0A1422),
    positive: Color(0xFF34D399), // profit / up = green
    negative: Color(0xFFF87171),
    warning: Color(0xFFFB923C), // low-stock amber-orange
    bg: Color(0xFF0B1120), // deep navy canvas
    card: Color(0xFF141C2E), // base surface
    cardRaised: Color(0xFF1B2438), // subtle tinted surfaces
    border: Color(0xFF273349), // hairline border / divider
    ink: Color(0xFFE6EBF3), // primary text
    inkMuted: Color(0xFF93A0B4), // secondary text
    navBar: Color(0xFF111A2A),
    heroOnAccent: Colors.white,
  );

  static ThemeData get light => _build(_lightPalette);
  static ThemeData get dark => _build(_darkPalette);

  static ThemeData _build(_Palette p) {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: brand,
          brightness: p.brightness,
        ).copyWith(
          primary: p.brand,
          onPrimary: p.onBrand,
          surface: p.card,
          surfaceContainerLowest: p.card,
          surfaceContainerLow: p.card,
          surfaceContainer: p.cardRaised,
          onSurface: p.ink,
          onSurfaceVariant: p.inkMuted,
          outlineVariant: p.border,
        );

    final textTheme = _typography(p.brightness);
    final cardColor = p.card;

    final appColors = AppColors(
      positive: p.positive,
      negative: p.negative,
      warning: p.warning,
      muted: p.cardRaised,
      navBar: p.navBar,
      onNavBar: p.inkMuted,
      heroOnAccent: p.heroOnAccent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: p.bg,
      textTheme: textTheme,
      extensions: [appColors],
      // Global icon size: shrink the default Material icon (24) so AppBar
      // actions, IconButtons and any size-less Icon render more compactly to
      // match the smaller type scale. Icons that pass an explicit `size:`
      // override this; those are trimmed individually at their call sites.
      iconTheme: IconThemeData(size: 21, color: p.ink),
      appBarTheme: AppBarTheme(
        backgroundColor: p.bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: p.ink,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: p.ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: p.border),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.brand,
          foregroundColor: p.onBrand,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.brand,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: p.border),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.card,
        hintStyle: textTheme.bodyMedium?.copyWith(color: p.inkMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: p.brand, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        side: BorderSide.none,
        backgroundColor: p.cardRaised,
      ),
      dividerTheme: DividerThemeData(color: p.border, space: 1),
    );
  }

  /// Inter, refined: tabular figures on every display/headline/title style so
  /// stat values, prices and counts never shift width as digits change, plus a
  /// touch of negative tracking on the large sizes so headings read as
  /// "designed" rather than default. Body sizes keep proportional figures and a
  /// 1.5 line-height for comfortable reading.
  /// Global multiplier on every text style. Material's default type scale runs
  /// large on smaller phones, so we render the whole app a touch more compact.
  /// Tweak this single value to scale all typography up or down at once.
  static const double _typeScale = 0.72;

  static TextTheme _typography(Brightness brightness) {
    final base = GoogleFonts.interTextTheme(
      ThemeData(brightness: brightness).textTheme,
    ).apply(fontFamilyFallback: const ['NotoSansBengali']);
    const tnum = [FontFeature.tabularFigures()];

    // Null-safe global scale: shrink the size when one is set, leave inherited
    // (null) sizes untouched so TextStyle.apply's assertion never trips.
    double? sz(TextStyle? s) =>
        s?.fontSize == null ? s?.fontSize : s!.fontSize! * _typeScale;

    TextStyle? display(TextStyle? s) => s?.copyWith(
      fontSize: sz(s),
      fontFeatures: tnum,
      letterSpacing: -0.8,
      height: 1.05,
    );
    TextStyle? headline(TextStyle? s) => s?.copyWith(
      fontSize: sz(s),
      fontFeatures: tnum,
      letterSpacing: -0.4,
      height: 1.1,
    );
    TextStyle? title(TextStyle? s) =>
        s?.copyWith(fontSize: sz(s), fontFeatures: tnum, letterSpacing: -0.1);
    TextStyle? body(TextStyle? s) => s?.copyWith(fontSize: sz(s), height: 1.5);
    TextStyle? label(TextStyle? s) => s?.copyWith(fontSize: sz(s));

    return base.copyWith(
      displayLarge: display(base.displayLarge),
      displayMedium: display(base.displayMedium),
      displaySmall: display(base.displaySmall),
      headlineLarge: headline(base.headlineLarge),
      headlineMedium: headline(base.headlineMedium),
      headlineSmall: headline(base.headlineSmall),
      titleLarge: title(base.titleLarge),
      titleMedium: title(base.titleMedium),
      titleSmall: title(base.titleSmall),
      bodyLarge: body(base.bodyLarge),
      bodyMedium: body(base.bodyMedium),
      bodySmall: body(base.bodySmall),
      labelLarge: label(base.labelLarge),
      labelMedium: label(base.labelMedium),
      labelSmall: label(base.labelSmall),
    );
  }
}

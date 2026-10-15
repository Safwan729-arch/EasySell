import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// App-specific colors not covered by [ColorScheme]. Access via
/// `Theme.of(context).extension<AppColors>()!`.
///
/// Values come from the EasySell design language (`EasySell Ui/new_design.md`
/// §3): light is "Pastel glass", dark is "Neon glass".
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
    required this.background,
    required this.sheet,
    required this.row,
    required this.field,
    required this.iconButton,
    required this.glowBorder,
    required this.textDim,
    required this.eyebrow,
    required this.sectionLabel,
    required this.link,
    required this.chipBlue,
    required this.successBg,
    required this.warningBg,
    required this.barIdle,
    required this.barEmpty,
    required this.gridLine,
    required this.stop,
    required this.violet,
  });

  final Color positive; // profit / up trends / "in stock"
  final Color negative; // losses / delete / remove
  /// low-stock / caution
  final Color warning;
  final Color muted; // soft tint: icon tiles, legend rows, active-tab pill
  final Color navBar; // bottom nav background
  final Color onNavBar; // inactive icon color on the nav bar
  /// text/icon on the hero (gradient) card
  final Color heroOnAccent;

  /// Screen canvas under [AppBackdrop]'s decoration.
  final Color background;

  /// Bottom sheets and dialogs.
  final Color sheet;

  /// Rows inside a sheet or card (Breakdown, Product detail).
  final Color row;

  /// Search field, inputs, idle pills.
  final Color field;

  /// Round header buttons.
  final Color iconButton;

  /// The thin outline on cards, rows, pills and fields. Glows in dark; a
  /// near-invisible hairline in light, where depth comes from shadows instead.
  final Color glowBorder;

  /// Idle nav icons, placeholders, disabled text. Too faint for body text.
  final Color textDim;

  /// Spaced-caps labels ("WHERE REVENUE COMES FROM").
  final Color eyebrow;

  /// Settings section labels ("PROFILE", "SHOP").
  final Color sectionLabel;

  /// Links ("View all ›"), active nav label, "MVP" text.
  final Color link;

  final Color chipBlue; // "MVP" chip, soft blue fills
  final Color successBg; // "Mon best" chip
  final Color warningBg; // low-stock card (light only; dark uses the card)
  final Color barIdle; // non-best bars
  final Color barEmpty; // zero-sales day stubs
  final Color gridLine; // dashed chart grid (dark only)
  final Color stop; // voice "stop" button
  final Color violet; // end of the brand gradient

  bool get _isDark => background.computeLuminance() < 0.2;

  /// Fill for everything selected or primary: blue→violet in light, a flat
  /// bright blue with a faint top-to-bottom shade in dark.
  Gradient get brandGradient => _isDark
      ? const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF5FA2FF), Color(0xFF3D82F5)],
        )
      : const LinearGradient(colors: [Color(0xFF3178FC), Color(0xFF7D53FA)]);

  /// The revenue hero card.
  Gradient get heroGradient => _isDark
      ? const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF12479A), Color(0xFF0F225A), Color(0xFF1A1F6E)],
        )
      : const LinearGradient(
          begin: Alignment(-1, -0.6),
          end: Alignment(1, 0.6),
          colors: [Color(0xFF1E4DC6), Color(0xFF3E67E7), Color(0xFF6B52F5)],
        );

  /// Depth for a card: a soft blue shadow in light, a faint outer glow in
  /// dark (the outline itself is [glowBorder]).
  List<BoxShadow> get cardShadow => _isDark
      ? const [BoxShadow(color: Color(0x243C6EFF), blurRadius: 22)]
      : const [
          BoxShadow(
            color: Color(0x144056BE),
            blurRadius: 30,
            offset: Offset(0, 10),
          ),
          BoxShadow(
            color: Color(0x0D4056BE),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ];

  /// The coloured glow under gradient / primary elements.
  List<BoxShadow> get primaryGlow => _isDark
      ? const [BoxShadow(color: Color(0x734D92FE), blurRadius: 22)]
      : const [
          BoxShadow(
            color: Color(0x4D6254FA),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ];

  /// The deeper glow under the hero card.
  List<BoxShadow> get heroGlow => _isDark
      ? const [BoxShadow(color: Color(0x403C6EFF), blurRadius: 28)]
      : const [
          BoxShadow(
            color: Color(0x473048DC),
            blurRadius: 36,
            offset: Offset(0, 16),
          ),
        ];

  /// A card surface: [ColorScheme.surface] fill, radius 22, theme depth.
  BoxDecoration card(BuildContext context, {double radius = 22, Color? color}) {
    return BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(radius),
      border: _isDark ? Border.all(color: glowBorder) : null,
      boxShadow: cardShadow,
    );
  }

  /// An outlined row inside a sheet or card (radius 16).
  BoxDecoration rowDecoration({double radius = 16}) => BoxDecoration(
    color: row,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: glowBorder),
  );

  @override
  AppColors copyWith({
    Color? positive,
    Color? negative,
    Color? warning,
    Color? muted,
    Color? navBar,
    Color? onNavBar,
    Color? heroOnAccent,
    Color? background,
    Color? sheet,
    Color? row,
    Color? field,
    Color? iconButton,
    Color? glowBorder,
    Color? textDim,
    Color? eyebrow,
    Color? sectionLabel,
    Color? link,
    Color? chipBlue,
    Color? successBg,
    Color? warningBg,
    Color? barIdle,
    Color? barEmpty,
    Color? gridLine,
    Color? stop,
    Color? violet,
  }) => AppColors(
    positive: positive ?? this.positive,
    negative: negative ?? this.negative,
    warning: warning ?? this.warning,
    muted: muted ?? this.muted,
    navBar: navBar ?? this.navBar,
    onNavBar: onNavBar ?? this.onNavBar,
    heroOnAccent: heroOnAccent ?? this.heroOnAccent,
    background: background ?? this.background,
    sheet: sheet ?? this.sheet,
    row: row ?? this.row,
    field: field ?? this.field,
    iconButton: iconButton ?? this.iconButton,
    glowBorder: glowBorder ?? this.glowBorder,
    textDim: textDim ?? this.textDim,
    eyebrow: eyebrow ?? this.eyebrow,
    sectionLabel: sectionLabel ?? this.sectionLabel,
    link: link ?? this.link,
    chipBlue: chipBlue ?? this.chipBlue,
    successBg: successBg ?? this.successBg,
    warningBg: warningBg ?? this.warningBg,
    barIdle: barIdle ?? this.barIdle,
    barEmpty: barEmpty ?? this.barEmpty,
    gridLine: gridLine ?? this.gridLine,
    stop: stop ?? this.stop,
    violet: violet ?? this.violet,
  );

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColors(
      positive: l(positive, other.positive),
      negative: l(negative, other.negative),
      warning: l(warning, other.warning),
      muted: l(muted, other.muted),
      navBar: l(navBar, other.navBar),
      onNavBar: l(onNavBar, other.onNavBar),
      heroOnAccent: l(heroOnAccent, other.heroOnAccent),
      background: l(background, other.background),
      sheet: l(sheet, other.sheet),
      row: l(row, other.row),
      field: l(field, other.field),
      iconButton: l(iconButton, other.iconButton),
      glowBorder: l(glowBorder, other.glowBorder),
      textDim: l(textDim, other.textDim),
      eyebrow: l(eyebrow, other.eyebrow),
      sectionLabel: l(sectionLabel, other.sectionLabel),
      link: l(link, other.link),
      chipBlue: l(chipBlue, other.chipBlue),
      successBg: l(successBg, other.successBg),
      warningBg: l(warningBg, other.warningBg),
      barIdle: l(barIdle, other.barIdle),
      barEmpty: l(barEmpty, other.barEmpty),
      gridLine: l(gridLine, other.gridLine),
      stop: l(stop, other.stop),
      violet: l(violet, other.violet),
    );
  }
}

/// Resolved color palette for one [Brightness]. Lets [AppTheme._build] stay a
/// single code path while light and dark each supply their own set.
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
    required this.sheet,
    required this.tint,
    required this.row,
    required this.field,
    required this.iconButton,
    required this.border,
    required this.divider,
    required this.ink,
    required this.inkMuted,
    required this.inkDim,
    required this.eyebrow,
    required this.sectionLabel,
    required this.link,
    required this.chipBlue,
    required this.successBg,
    required this.warningBg,
    required this.barIdle,
    required this.barEmpty,
    required this.gridLine,
    required this.stop,
    required this.violet,
    required this.dragHandle,
  });

  final Brightness brightness;
  final Color brand; // primary
  final Color onBrand; // text/icon on a primary fill
  final Color positive;
  final Color negative;
  final Color warning;
  final Color bg; // screen canvas
  final Color card; // cards, list cards
  final Color sheet; // bottom sheets, dialogs
  final Color tint; // soft tinted surfaces
  final Color row; // rows inside a sheet or card
  final Color field; // inputs, idle pills
  final Color iconButton; // round header buttons
  final Color border; // card / field outline
  final Color divider; // hairline rules
  final Color ink; // primary text
  final Color inkMuted; // secondary text
  final Color inkDim; // disabled / idle icons
  final Color eyebrow;
  final Color sectionLabel;
  final Color link;
  final Color chipBlue;
  final Color successBg;
  final Color warningBg;
  final Color barIdle;
  final Color barEmpty;
  final Color gridLine;
  final Color stop;
  final Color violet;
  final Color dragHandle;

  bool get isDark => brightness == Brightness.dark;
}

/// Material 3 theme in the EasySell design language. Light ("Pastel glass")
/// and dark ("Neon glass") share one structural build: the same radii,
/// heights and component shapes, with only colour and depth changing.
class AppTheme {
  const AppTheme._();

  static const Color brand = Color(0xFF2668F9); // light primary blue
  static const Color brandDeep = Color(0xFF1D4FE8); // pressed / deep

  static const _Palette _lightPalette = _Palette(
    brightness: Brightness.light,
    brand: brand,
    onBrand: Colors.white,
    positive: Color(0xFF16A34A),
    negative: Color(0xFFDE2625),
    warning: Color(0xFFF2600C),
    bg: Color(0xFFF3F4FE),
    card: Color(0xFFFFFFFF),
    sheet: Color(0xFFFFFFFF),
    tint: Color(0xFFF2F4FE),
    row: Color(0xFFF4F6FD),
    field: Color(0xFFFFFFFF),
    iconButton: Color(0xFFFFFFFF),
    border: Color(0xFFE4E8F8), // derived: a hairline that reads on white
    divider: Color(0xFFE6E9F7), // derived
    ink: Color(0xFF0F1430),
    inkMuted: Color(0xFF6B7590),
    inkDim: Color(0xFF8992A8),
    eyebrow: Color(0xFF5A5E92),
    sectionLabel: Color(0xFF2F55F0),
    link: Color(0xFF1D4FE8),
    chipBlue: Color(0xFFECF1FE),
    successBg: Color(0xFFDFF6E6),
    warningBg: Color(0xFFFDF5F2),
    barIdle: Color(0xFFE0E6FD),
    barEmpty: Color(0xFFEBEFFE),
    gridLine: Color(0xFFE6E9F7),
    stop: Color(0xFFFDADA7),
    violet: Color(0xFF7B4DFA),
    dragHandle: Color(0xFFC9D1EE), // derived
  );

  static const _Palette _darkPalette = _Palette(
    brightness: Brightness.dark,
    brand: Color(0xFF4D92FE),
    onBrand: Color(0xFF06102A),
    positive: Color(0xFF3FE6C4), // mint
    negative: Color(0xFFFF8397),
    warning: Color(0xFFFFC23F), // amber
    bg: Color(0xFF07112E),
    card: Color(0xFF0E1C3C),
    sheet: Color(0xFF0A1838),
    tint: Color(0xFF13234A), // derived
    row: Color(0xFF0F1F41),
    field: Color(0xFF0D1C49),
    iconButton: Color(0xFF111E42),
    border: Color(0x525282FF), // rgba(82,130,255,0.32)
    divider: Color(0xFF1C3270),
    ink: Color(0xFFF2F5FF),
    inkMuted: Color(0xFFB3BFE3),
    inkDim: Color(0xFF6273A8),
    eyebrow: Color(0xFF8FA9F5),
    sectionLabel: Color(0xFF8FA9F5),
    link: Color(0xFF6BB5FF),
    chipBlue: Color(0xFF152C5B),
    successBg: Color(0xFF123B50),
    warningBg: Color(0xFF0E1C3C), // dark keeps the plain glass card
    barIdle: Color(0xFF3D4B6E),
    barEmpty: Color(0xFF263857),
    gridLine: Color(0xFF263857),
    stop: Color(0xFFFDADA7),
    violet: Color(0xFF8B5CF6),
    dragHandle: Color(0xFF7383C2),
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
          secondaryContainer: p.chipBlue,
          onSecondaryContainer: p.link,
          error: p.negative,
          surface: p.card,
          surfaceContainerLowest: p.card,
          surfaceContainerLow: p.card,
          surfaceContainer: p.tint,
          surfaceContainerHigh: p.row,
          surfaceContainerHighest: p.tint,
          onSurface: p.ink,
          onSurfaceVariant: p.inkMuted,
          outline: p.inkDim,
          outlineVariant: p.divider,
        );

    final textTheme = _typography(p.brightness);

    final appColors = AppColors(
      positive: p.positive,
      negative: p.negative,
      warning: p.warning,
      muted: p.tint,
      navBar: p.isDark ? p.sheet : p.card,
      onNavBar: p.isDark ? p.inkMuted : p.inkDim,
      heroOnAccent: Colors.white,
      background: p.bg,
      sheet: p.sheet,
      row: p.row,
      field: p.field,
      iconButton: p.iconButton,
      glowBorder: p.border,
      textDim: p.inkDim,
      eyebrow: p.eyebrow,
      sectionLabel: p.sectionLabel,
      link: p.link,
      chipBlue: p.chipBlue,
      successBg: p.successBg,
      warningBg: p.warningBg,
      barIdle: p.barIdle,
      barEmpty: p.barEmpty,
      gridLine: p.gridLine,
      stop: p.stop,
      violet: p.violet,
    );

    // Light: depth is a soft blue shadow and there is no visible outline.
    // Dark: no shadow, a 1px glowing outline instead.
    final cardSide = p.isDark ? BorderSide(color: p.border) : BorderSide.none;
    final fieldSide = BorderSide(color: p.border);
    OutlineInputBorder fieldBorder(BorderSide side) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: side,
    );
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    final buttonText = textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: scheme,
      // Transparent so each page's [AppBackdrop] (blurs / glow / wave lines)
      // shows through. Every route wraps its page in a backdrop; see
      // app_router.dart and main_shell.dart.
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: p.bg,
      textTheme: textTheme,
      extensions: [appColors],
      // Global icon size: a touch under Material's 24 so AppBar actions,
      // IconButtons and any size-less Icon render compactly. Icons that pass
      // an explicit `size:` override this.
      iconTheme: IconThemeData(size: 21, color: p.ink),
      appBarTheme: AppBarTheme(
        // Transparent at rest so the backdrop's corner decoration runs under
        // the title, as in the mockups; solid once content scrolls beneath it
        // so text never shows through.
        backgroundColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.scrolledUnder)
              ? p.bg.withValues(alpha: 0.96)
              : Colors.transparent,
        ),
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        foregroundColor: p.ink,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          color: p.ink,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.card,
        elevation: p.isDark ? 0 : 6,
        shadowColor: p.isDark
            ? Colors.transparent
            : const Color(0x404056BE), // soft blue shadow
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: cardSide,
        ),
        clipBehavior: Clip.antiAlias,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? p.ink.withValues(alpha: 0.10)
                : p.brand,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled)
                ? p.ink.withValues(alpha: 0.38)
                : p.onBrand,
          ),
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(54)),
          shape: WidgetStatePropertyAll(buttonShape),
          textStyle: WidgetStatePropertyAll(buttonText),
          elevation: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.disabled) ? 0 : 4,
          ),
          shadowColor: WidgetStatePropertyAll(
            p.isDark ? const Color(0x994D92FE) : const Color(0x806254FA),
          ),
          // The gradient is painted with [Ink], on the button's Material, so
          // the press ripple still draws on top of it. Material does not clip
          // ink to its shape, so the gradient carries the same shape itself;
          // no call site overrides a FilledButton's shape.
          backgroundBuilder: (context, states, child) {
            if (states.contains(WidgetState.disabled)) return child!;
            final colors = Theme.of(context).extension<AppColors>()!;
            return Ink(
              decoration: ShapeDecoration(
                shape: buttonShape,
                gradient: colors.brandGradient,
              ),
              child: child,
            );
          },
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.link,
          backgroundColor: p.isDark ? p.field : p.card,
          minimumSize: const Size.fromHeight(54),
          shape: buttonShape,
          side: BorderSide(color: p.isDark ? p.border : p.border),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.link),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.field,
        hintStyle: textTheme.bodyLarge?.copyWith(color: p.inkMuted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 17,
        ),
        border: fieldBorder(fieldSide),
        enabledBorder: fieldBorder(fieldSide),
        focusedBorder: fieldBorder(BorderSide(color: p.brand, width: 1.6)),
        errorBorder: fieldBorder(BorderSide(color: p.negative)),
        focusedErrorBorder: fieldBorder(
          BorderSide(color: p.negative, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: StadiumBorder(
          side: p.isDark ? BorderSide(color: p.border) : BorderSide.none,
        ),
        side: p.isDark ? BorderSide(color: p.border) : BorderSide.none,
        backgroundColor: p.isDark ? p.field : p.card,
        selectedColor: p.brand,
        secondarySelectedColor: p.brand,
        checkmarkColor: p.onBrand,
        labelStyle: textTheme.labelLarge?.copyWith(
          color: p.ink,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: p.onBrand,
          fontWeight: FontWeight.w700,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? p.brand
                : (p.isDark ? p.field : p.card),
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) =>
                states.contains(WidgetState.selected) ? p.onBrand : p.inkMuted,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: p.border)),
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          textStyle: WidgetStatePropertyAll(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.sheet,
        modalBackgroundColor: p.sheet,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: p.dragHandle,
        dragHandleSize: const Size(40, 5),
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          side: p.isDark ? BorderSide(color: p.border) : BorderSide.none,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.sheet,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
          side: p.isDark ? BorderSide(color: p.border) : BorderSide.none,
        ),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.sheet,
        surfaceTintColor: Colors.transparent,
        headerForegroundColor: p.ink,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(32),
          side: p.isDark ? BorderSide(color: p.border) : BorderSide.none,
        ),
        dividerColor: p.divider,
        todayBorder: BorderSide(color: p.brand),
        dayForegroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.onBrand;
          if (states.contains(WidgetState.disabled)) return p.inkDim;
          return p.ink;
        }),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? p.brand : null,
        ),
        cancelButtonStyle: TextButton.styleFrom(foregroundColor: p.link),
        confirmButtonStyle: OutlinedButton.styleFrom(
          foregroundColor: p.link,
          shape: const StadiumBorder(),
          side: BorderSide(color: p.border),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.brand,
        foregroundColor: p.onBrand,
        shape: const StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(color: p.divider, space: 1),
    );
  }

  /// Inter (Noto Sans Bengali for Bangla). Tabular figures on every
  /// display/headline/title style so stat values, prices and counts never shift
  /// width as digits change, and a touch of negative tracking on the large
  /// sizes. Body sizes keep proportional figures and a 1.5 line-height.
  ///
  /// Sizes are left null here on purpose: Material merges its type geometry in
  /// later, inside `Theme.of`. (An old `_typeScale` multiplier assumed they were
  /// set; it never applied, and was removed in the EasySell reskin.)
  static TextTheme _typography(Brightness brightness) {
    final base = GoogleFonts.interTextTheme(
      ThemeData(brightness: brightness).textTheme,
    ).apply(fontFamilyFallback: const ['NotoSansBengali']);
    const tnum = [FontFeature.tabularFigures()];

    TextStyle? display(TextStyle? s) =>
        s?.copyWith(fontFeatures: tnum, letterSpacing: -0.8, height: 1.05);
    TextStyle? headline(TextStyle? s) =>
        s?.copyWith(fontFeatures: tnum, letterSpacing: -0.4, height: 1.1);
    TextStyle? title(TextStyle? s) =>
        s?.copyWith(fontFeatures: tnum, letterSpacing: -0.1);
    TextStyle? body(TextStyle? s) => s?.copyWith(height: 1.5);

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
    );
  }
}

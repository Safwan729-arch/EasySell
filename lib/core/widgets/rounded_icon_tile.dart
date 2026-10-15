import 'package:flutter/material.dart';

/// Solid palette for product letter tiles (EasySell §3.3): green, purple, red,
/// orange. A product is mapped to a stable colour via [tileColorFor] so the same
/// name always gets the same hue across screens. The colour follows the
/// product, not its category: categories are user-made and unbounded.
const List<Color> kTilePalette = [
  Color(0xFF18A24A), // green
  Color(0xFF7934F1), // purple
  Color(0xFFDE2625), // red
  Color(0xFFF4680A), // orange
];

/// The same four hues, a step brighter for the dark theme.
const List<Color> kTilePaletteDark = [
  Color(0xFF3DB86A),
  Color(0xFF8B5CF6),
  Color(0xFFE5484D),
  Color(0xFFF97316),
];

/// Deterministic color for a tile keyed by [seed] (e.g. a product name) so the
/// hue is stable run-to-run and across screens. [dark] picks the dark shade.
Color tileColorFor(String seed, {bool dark = false}) {
  final palette = dark ? kTilePaletteDark : kTilePalette;
  if (seed.isEmpty) return palette.first;
  var hash = 0;
  for (final c in seed.codeUnits) {
    hash = (hash * 31 + c) & 0x7fffffff;
  }
  return palette[hash % palette.length];
}

/// Rounded-square icon container used as the leading element of list rows. By
/// default it renders a tinted background with a colored icon; pass [filled] for
/// a solid-color tile with a white icon.
class RoundedIconTile extends StatelessWidget {
  const RoundedIconTile({
    super.key,
    required this.icon,
    this.color,
    this.size = 44,
    this.filled = false,
  });

  final IconData icon;
  final Color? color;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: filled ? accent : accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        icon,
        color: filled ? Colors.white : accent,
        size: size * 0.5,
      ),
    );
  }
}

/// A rounded-square tile that displays a text glyph (e.g. a product's initial).
/// Defaults to a solid bright tile with a white glyph (the redesign style); pass
/// [filled] false for the older tinted look.
class RoundedTextTile extends StatelessWidget {
  const RoundedTextTile({
    super.key,
    required this.text,
    this.color,
    this.size = 44,
    this.filled = true,
  });

  final String text;
  final Color? color;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = color ?? tileColorFor(text, dark: dark);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? accent : accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: filled ? Colors.white : accent,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.4,
        ),
      ),
    );
  }
}

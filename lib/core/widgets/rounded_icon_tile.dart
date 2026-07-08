import 'package:flutter/material.dart';

/// Bright solid palette for product/category letter tiles. A product is mapped
/// to a stable color via [tileColorFor] so the same name always gets the same
/// hue across screens (dashboard, inventory, sell).
const List<Color> kTilePalette = [
  Color(0xFF16A34A), // green
  Color(0xFFEA580C), // orange
  Color(0xFFDC2626), // red
  Color(0xFF7C3AED), // purple
  Color(0xFF0D9488), // teal
  Color(0xFFDB2777), // pink
  Color(0xFF2563EB), // blue
  Color(0xFF65A30D), // olive
];

/// Deterministic color for a tile keyed by [seed] (e.g. a product name) so the
/// hue is stable run-to-run and across screens.
Color tileColorFor(String seed) {
  if (seed.isEmpty) return kTilePalette.first;
  var hash = 0;
  for (final c in seed.codeUnits) {
    hash = (hash * 31 + c) & 0x7fffffff;
  }
  return kTilePalette[hash % kTilePalette.length];
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
    final accent = color ?? tileColorFor(text);
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

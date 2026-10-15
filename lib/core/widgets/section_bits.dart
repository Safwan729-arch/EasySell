import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../l10n/l10n_ext.dart';

/// Spaced-caps label above a section or inside a card ("TOP PERFORMER",
/// "WHERE REVENUE COMES FROM"): 13 / 600, +1.8 tracking, `eyebrow` colour.
class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelLarge?.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        // Tracking pulls Bangla conjuncts apart ("বিক্রেতা" renders as
        // "বিক্রে৽তা"), and Bangla has no capitals to space out anyway.
        letterSpacing: hasBangla(text) ? 0 : 1.8,
        color: color ?? theme.extension<AppColors>()!.eyebrow,
      ),
    );
  }
}

/// Whether [text] contains any Bengali-script character (U+0980–U+09FF).
/// Letter-spacing must stay off for such text: it breaks conjunct shaping.
bool hasBangla(String text) =>
    text.runes.any((r) => r >= 0x0980 && r <= 0x09FF);

/// "View all ›" in link blue. A [TextButton] underneath, so it keeps a
/// 48 dp tap target and the theme's press feedback.
class ViewAllLink extends StatelessWidget {
  const ViewAllLink({super.key, required this.onPressed, this.label});

  final VoidCallback onPressed;

  /// Defaults to the localized "View all".
  final String? label;

  @override
  Widget build(BuildContext context) {
    final link = Theme.of(context).extension<AppColors>()!.link;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: link,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        textStyle: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label ?? context.l10n.dashboard_viewAll),
          const SizedBox(width: 2),
          const Icon(Icons.chevron_right_rounded, size: 20),
        ],
      ),
    );
  }
}

/// A Home attention card: an icon and title with "View all ›" on the right,
/// then a body. [tinted] gives the light-mode peach "Low stock" treatment
/// (`warningBg` with a faint peach border); dark mode always uses the plain
/// glass card, per the mockups.
class AlertCard extends StatelessWidget {
  const AlertCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onViewAll,
    required this.child,
    this.onTap,
    this.tinted = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final VoidCallback onViewAll;
  final Widget child;
  final VoidCallback? onTap;
  final bool tinted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final isDark = theme.brightness == Brightness.dark;
    final peach = tinted && !isDark;
    final decoration = colors.card(
      context,
      color: peach ? colors.warningBg : null,
    );
    return DecoratedBox(
      decoration: peach
          ? decoration.copyWith(
              border: Border.all(color: const Color(0xFFF9DCCF)),
              boxShadow: const [],
            )
          : decoration,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 8, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 24, color: iconColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        // Two lines: a long Bangla title beside "View all"
                        // would otherwise be cut mid-word on a 360 dp phone.
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ViewAllLink(onPressed: onViewAll),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: child,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

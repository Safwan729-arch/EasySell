import 'package:flutter/material.dart';

import '../config/theme.dart';
import 'app_backdrop.dart';

/// The top of a bottom sheet: a 28 / 700 title and an optional muted-blue
/// subtitle ("Today · exact figures"), with the dark theme's wave lines in the
/// corner behind them.
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Kept inside the sheet's top edge: drawn any higher, it would spill
        // over the scrim above the sheet.
        const Positioned(
          top: -12,
          right: -20,
          width: 240,
          height: 120,
          child: WaveLines(height: 120),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  color: colors.eyebrow,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

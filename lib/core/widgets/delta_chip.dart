import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Small colored delta indicator like `↗ 8.2%` (green) / `↘ 10% ` (red),
/// matching the reference design — a leading trend arrow and colored text, no
/// pill background. Pass a signed [percent].
class DeltaChip extends StatelessWidget {
  const DeltaChip({super.key, required this.percent});

  final double percent;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final up = percent >= 0;
    final color = up ? colors.positive : colors.negative;
    final sign = up ? '+' : '';
    // Trim a trailing ".0" so 14.0 reads "14%" but 8.2 stays "8.2%".
    var num = percent.abs().toStringAsFixed(1);
    if (num.endsWith('.0')) num = num.substring(0, num.length - 2);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 3),
        Text(
          '$sign$num%',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

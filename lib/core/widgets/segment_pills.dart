import 'package:flutter/material.dart';

import '../config/motion.dart';
import 'brand_fill.dart';
import 'pressable.dart';

/// Horizontal pill selector (Today / Week / Month / Year), 46 dp high. The active
/// pill wears the brand fill; idle pills are white (light) or outlined glass
/// (dark). Generic over the value type [T].
class SegmentPills<T> extends StatelessWidget {
  const SegmentPills({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.expand = false,
  });

  final List<T> values;

  /// The highlighted value, or null to highlight none (Reports in day-mode).
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  /// Equal-width pills sharing the row (the period selectors), instead of a
  /// sideways-scrolling row of natural-width pills (filter chips, whose count
  /// is open-ended). Needs a bounded width.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!expand) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        // Let the light-mode shadows and dark-mode glow spill past the row
        // instead of being sliced off at its edges.
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (var i = 0; i < values.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              _Pill(
                label: labelOf(values[i]),
                selected: values[i] == selected,
                onTap: () => onChanged(values[i]),
                theme: theme,
                horizontalPadding: 22,
              ),
            ],
          ],
        ),
      );
    }
    // Three natural-width pills plus the calendar button overflow a 360 dp
    // phone, so period pills share the row; a long label scales down.
    return Row(
      children: [
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _Pill(
              label: labelOf(values[i]),
              selected: values[i] == selected,
              onTap: () => onChanged(values[i]),
              theme: theme,
            ),
          ),
        ],
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
    this.horizontalPadding = 10,
  });

  final double horizontalPadding;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final duration = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.fast;
    return PressableScale(
      onTap: onTap,
      scale: 0.95,
      child: AnimatedContainer(
        duration: duration,
        curve: AppMotion.easeOut,
        height: 46,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        decoration: selected
            ? brandFillDecoration(context)
            : idleFillDecoration(context),
        child: AnimatedDefaultTextStyle(
          duration: duration,
          curve: AppMotion.easeOut,
          style:
              theme.textTheme.titleSmall?.copyWith(
                fontSize: 15,
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ) ??
              const TextStyle(),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1),
          ),
        ),
      ),
    );
  }
}

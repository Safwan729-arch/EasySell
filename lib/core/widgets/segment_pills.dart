import 'package:flutter/material.dart';

import '../config/motion.dart';
import 'pressable.dart';

/// Horizontal pill selector (Today / Week / Month / Year). Active pill is solid
/// orange with white text; inactive pills sit on a muted background. Generic
/// over the value type [T].
class SegmentPills<T> extends StatelessWidget {
  const SegmentPills({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final v in values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _Pill(
                label: labelOf(v),
                selected: v == selected,
                onTap: () => onChanged(v),
                theme: theme,
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: ShapeDecoration(
          color: selected
              ? scheme.primary
              : theme.cardTheme.color ?? scheme.surfaceContainerLowest,
          shape: StadiumBorder(
            side: selected
                ? BorderSide.none
                : BorderSide(color: scheme.outlineVariant),
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: duration,
          curve: AppMotion.easeOut,
          style:
              theme.textTheme.labelLarge?.copyWith(
                color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ) ??
              const TextStyle(),
          child: Text(label),
        ),
      ),
    );
  }
}

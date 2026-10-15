import 'package:flutter/material.dart';

import '../config/haptics.dart';
import '../config/motion.dart';
import 'brand_fill.dart';

/// One rounded track holding a few options (Cash / Credit, English / বাংলা,
/// Light / Dark). The selected option wears the brand fill; the others sit on
/// the track. Pass [iconOf] to show an icon before each label (Settings).
class TwoOptionSegment<T> extends StatelessWidget {
  const TwoOptionSegment({
    super.key,
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.iconOf,
    this.enabled = true,
    this.height = 54,
  });

  final List<T> values;

  /// The highlighted option, or null for none (History while a day is picked).
  final T? selected;
  final String Function(T) labelOf;
  final IconData Function(T)? iconOf;
  final ValueChanged<T> onChanged;
  final bool enabled;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final duration = AppMotion.reduced(context)
        ? Duration.zero
        : AppMotion.fast;
    // Idle options carry a transparent *gradient* rather than no decoration:
    // the AnimatedContainer lerps to and from the brand gradient, and a
    // ShapeDecoration mid-way between a colour and a gradient asserts.
    const idle = ShapeDecoration(
      shape: StadiumBorder(),
      gradient: LinearGradient(
        colors: [Colors.transparent, Colors.transparent],
      ),
    );
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: idleFillDecoration(context),
      child: Row(
        children: [
          for (final v in values)
            Expanded(
              child: Semantics(
                button: true,
                selected: v == selected,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: !enabled || v == selected
                      ? null
                      : () {
                          AppHaptics.tap();
                          onChanged(v);
                        },
                  child: AnimatedContainer(
                    duration: duration,
                    curve: AppMotion.easeOut,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: v == selected
                        ? brandFillDecoration(context)
                        : idle,
                    child: _OptionLabel(
                      label: labelOf(v),
                      icon: iconOf?.call(v),
                      color: v == selected
                          ? scheme.onPrimary
                          : scheme.onSurfaceVariant,
                      selected: v == selected,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OptionLabel extends StatelessWidget {
  const _OptionLabel({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall?.copyWith(
      fontSize: 16,
      color: color,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 10),
          ],
          Text(label, maxLines: 1, style: style),
        ],
      ),
    );
  }
}

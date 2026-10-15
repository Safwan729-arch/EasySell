import 'package:flutter/material.dart';

import '../config/haptics.dart';
import 'brand_fill.dart';

/// Circular calendar affordance beside a period selector. Opens a date picker
/// bounded to the past year through today; a picked day is reported via [onPick].
/// Wears the brand fill while a day is active. Shared by the Home dashboard
/// and the Reports tab so both drill into a single past day the same way.
class CalendarDayButton extends StatelessWidget {
  const CalendarDayButton({
    super.key,
    required this.selectedDay,
    required this.onPick,
    this.firstDate,
    this.size = 46,
  });

  final DateTime? selectedDay;
  final ValueChanged<DateTime> onPick;

  /// Lower bound of the picker. When null, defaults to one year before today
  /// (legacy behavior). Callers pass the shop's earliest sale date so the whole
  /// sales history is reachable.
  final DateTime? firstDate;

  /// Diameter of the circular button. Icon and tap radius scale with it so the
  /// Reports card can use a slightly smaller button than the dashboard header.
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = selectedDay != null;
    return InkResponse(
      onTap: () async {
        AppHaptics.tap();
        final now = DateTime.now();
        final picked = await showDatePicker(
          context: context,
          initialDate: selectedDay ?? now,
          firstDate: firstDate ?? DateTime(now.year - 1, now.month, now.day),
          lastDate: now,
        );
        if (picked != null) {
          onPick(DateTime(picked.year, picked.month, picked.day));
        }
      },
      radius: size * 0.6,
      child: Container(
        width: size,
        height: size,
        decoration: active
            ? brandFillDecoration(context, shape: const CircleBorder())
            : idleFillDecoration(context, shape: const CircleBorder()),
        child: Icon(
          Icons.calendar_today_outlined,
          size: size * 0.45,
          color: active
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Dismissible chip naming the drilled-into day; its delete action clears the day
/// filter back to the running-period view. Shared by Home and Reports.
class DayFilterChip extends StatelessWidget {
  const DayFilterChip({super.key, required this.label, required this.onClear});

  final String label;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return InputChip(
      label: Text(label),
      onDeleted: onClear,
      deleteIcon: const Icon(Icons.close_rounded, size: 16),
    );
  }
}

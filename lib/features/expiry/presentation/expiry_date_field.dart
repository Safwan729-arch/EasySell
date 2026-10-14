import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../domain/expiry_dates.dart';
import 'today_provider.dart';

/// Medium date in the app's language ("Oct 20, 2026" / "২০ অক্টো, ২০২৬").
String formatExpiryDate(BuildContext context, DateTime d) =>
    DateFormat.yMMMd(Localizations.localeOf(context).languageCode).format(d);

/// Asks before accepting a past date or one more than five years ahead
/// (spec §5 "Odd dates"). Returns true to keep [picked].
Future<bool> confirmOddExpiryDate(
  BuildContext context,
  DateTime picked,
  DateTime today,
) async {
  final kind = classifyExpiryDate(picked, today);
  if (kind == OddDate.none) return true;
  final l10n = context.l10n;
  final keep = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(
        kind == OddDate.past
            ? l10n.expiry_pastDateTitle
            : l10n.expiry_farDateTitle,
      ),
      content: Text(
        kind == OddDate.past
            ? l10n.expiry_pastDateBody
            : l10n.expiry_farDateBody(formatExpiryDate(ctx, picked)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.expiry_changeDate),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.expiry_saveAnyway),
        ),
      ],
    ),
  );
  return keep == true;
}

/// An optional expiry date: tap to pick, ✕ to clear. Odd dates are confirmed.
class ExpiryDateField extends ConsumerWidget {
  const ExpiryDateField({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.enabled = true,
  });

  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? label;
  final bool enabled;

  Future<void> _pick(BuildContext context, WidgetRef ref) async {
    final today = ref.read(todayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? today,
      firstDate: DateTime(today.year - 2),
      lastDate: DateTime(today.year + 30),
    );
    if (picked == null || !context.mounted) return;
    if (await confirmOddExpiryDate(context, picked, today)) {
      onChanged(dateOnly(picked));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final date = value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: enabled ? () => _pick(context, ref) : null,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label ?? l10n.expiry_dateLabel,
            suffixIcon: date == null
                ? const Icon(Icons.event_outlined)
                : IconButton(
                    tooltip: l10n.expiry_dateClear,
                    icon: const Icon(Icons.close),
                    onPressed: enabled ? () => onChanged(null) : null,
                  ),
          ),
          child: Text(
            date == null
                ? l10n.expiry_dateOptional
                : formatExpiryDate(context, date),
            style: date == null
                ? theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : theme.textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }
}

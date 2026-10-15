import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import 'restock_prefs.dart';

/// Settings: how often the shopkeeper restocks, which sets how many days the
/// buy suggestion covers (restock spec §4.3).
class RestockDaysTile extends ConsumerWidget {
  const RestockDaysTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final days = ref.watch(restockDaysProvider);
    return ListTile(
      leading: const Icon(Icons.shopping_basket_outlined),
      title: Text(l10n.settings_restockEvery(days)),
      onTap: () async {
        final picked = await showDialog<int>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(l10n.settings_restockEveryTitle),
            children: [
              for (final d in restockDayChoices)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(d),
                  child: Row(
                    children: [
                      Expanded(child: Text(l10n.restockPlan_daysShort(d))),
                      if (d == days) const Icon(Icons.check, size: 18),
                    ],
                  ),
                ),
            ],
          ),
        );
        if (picked != null) {
          await ref.read(restockDaysProvider.notifier).set(picked);
        }
      },
    );
  }
}

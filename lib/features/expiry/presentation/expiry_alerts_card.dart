import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../domain/expiry_alerts.dart';
import 'expiry_providers.dart';
import 'expiry_text.dart';

/// Home's "Expiring & expired" card (spec §5). Hidden when there is nothing
/// to say, so shops that never record dates see no change.
class ExpiryAlertsCard extends ConsumerWidget {
  const ExpiryAlertsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(expiryAlertsProvider);
    if (alerts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.event_busy_outlined,
                    size: 18,
                    color: colors.negative,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.expiry_cardTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.push(AppRoutes.alerts),
                    child: Text(l10n.dashboard_viewAll),
                  ),
                ],
              ),
              for (final a in alerts.take(4))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    a.kind == ExpiryAlertKind.expired
                        ? Icons.error_outline
                        : Icons.schedule,
                    color: a.kind == ExpiryAlertKind.expired
                        ? colors.negative
                        : colors.warning,
                  ),
                  title: Text(expiryAlertText(l10n, a)),
                  onTap: () => context.push('/inventory/${a.product.id}'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

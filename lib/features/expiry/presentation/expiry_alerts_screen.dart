import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../domain/expiry_alerts.dart';
import 'expiry_date_field.dart';
import 'expiry_providers.dart';
import 'expiry_text.dart';

/// Every expiry alert -- opened from the bell and from a reminder tap.
class ExpiryAlertsScreen extends ConsumerWidget {
  const ExpiryAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final alerts = ref.watch(expiryAlertsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.expiry_alertsTitle)),
      body: alerts.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      size: 48,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.dashboard_notificationsCaughtUp,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.dashboard_notificationsHint,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: alerts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final a = alerts[i];
                final expired = a.kind == ExpiryAlertKind.expired;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    expired ? Icons.error_outline : Icons.schedule,
                    color: expired ? colors.negative : colors.warning,
                  ),
                  title: Text(expiryAlertText(l10n, a)),
                  subtitle: Text(formatExpiryDate(context, a.expiryDate)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/inventory/${a.product.id}'),
                );
              },
            ),
    );
  }
}

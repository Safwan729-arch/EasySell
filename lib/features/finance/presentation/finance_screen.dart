import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/app_card.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/cash_flow_alerts.dart';
import '../domain/finance_health.dart';
import '../domain/financing_match.dart';
import 'finance_providers.dart';
import 'finance_text.dart';
import 'money_health_card.dart';

/// Money health (spec §6): the week's money in and out, every warning, and
/// the example financing options matched to the shop.
class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final health = ref.watch(financeHealthProvider);
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';

    return Scaffold(
      appBar: AppBar(title: Text(l10n.finance_title)),
      body: switch (health) {
        AsyncData(:final value) => _Body(health: value, currency: currency),
        AsyncError() => _ErrorMessage(
          onRetry: () => ref.invalidate(financeHealthProvider),
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.health, required this.currency});

  final FinanceHealth health;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final alerts = cashFlowAlerts(health);
    final matches = matchFinancing(health);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    String money(double v) => Money.format(v, currencyCode: currency);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _Heading(l10n.finance_last7Days),
        AppCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MoneyFlowRow(health: health, currency: currency),
              const Divider(height: 28),
              _Row(l10n.finance_rowCashSales, money(health.cashSales7d)),
              _Row(l10n.finance_rowDigitalSales, money(health.digitalSales7d)),
              _Row(l10n.finance_rowCollected, money(health.collected7d)),
              _Row(l10n.finance_rowMoneyIn, money(health.cashIn7d), bold: true),
              const SizedBox(height: 8),
              _Row(l10n.finance_rowRestocks, money(health.restockSpend7d)),
              _Row(
                l10n.finance_rowMoneyOut,
                money(health.cashOut7d),
                bold: true,
              ),
              const SizedBox(height: 8),
              _Row(
                l10n.finance_rowCreditGiven,
                money(health.creditSales7d),
                dim: true,
              ),
              const SizedBox(height: 6),
              Text(l10n.finance_outNote, style: muted),
            ],
          ),
        ),
        _Heading(l10n.finance_alertsTitle),
        if (alerts.isEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.check_circle_outline, color: colors.positive),
            title: Text(l10n.finance_allGood),
          )
        else
          for (final a in alerts)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.warning_amber_rounded,
                color: a is OverdueAlert ? colors.negative : colors.warning,
              ),
              title: Text(alertText(l10n, a, currency)),
              subtitle: switch (alertDetail(l10n, a)) {
                final d? => Text(d),
                null => null,
              },
              // The late customers are on the Customers screen.
              onTap: a is OverdueAlert
                  ? () => context.push(AppRoutes.customers)
                  : null,
              trailing: a is OverdueAlert
                  ? const Icon(Icons.chevron_right)
                  : null,
            ),
        _Heading(l10n.finance_financingTitle),
        Text(l10n.finance_financingIntro, style: muted),
        const SizedBox(height: 10),
        for (final m in matches)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FinancingTile(match: m, health: health, currency: currency),
          ),
        const SizedBox(height: 4),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(child: Text(l10n.finance_disclaimer, style: muted)),
          ],
        ),
      ],
    );
  }
}

class _FinancingTile extends StatelessWidget {
  const _FinancingTile({
    required this.match,
    required this.health,
    required this.currency,
  });

  final FinancingMatch match;
  final FinanceHealth health;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final fits = match.fits;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  financingName(l10n, match.kind),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: fits ? colors.successBg : colors.muted,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  fits ? l10n.finance_fits : l10n.finance_notYet,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fits
                        ? colors.positive
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            financingSubtitle(l10n, match.kind),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                fits ? Icons.check_rounded : Icons.flag_outlined,
                size: 18,
                color: fits ? colors.positive : colors.warning,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  financingReason(l10n, match, health, currency),
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          if (fits && match.upTo > 0) ...[
            const SizedBox(height: 4),
            Text(
              l10n.finance_upTo(
                Money.format(match.upTo, currencyCode: currency),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 18, bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value, {this.bold = false, this.dim = false});

  final String label;
  final String value;
  final bool bold;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: bold ? FontWeight.w700 : null,
      color: dim ? theme.colorScheme.onSurfaceVariant : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 8),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              context.l10n.finance_loadError,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.l10n.common_retry),
            ),
          ],
        ),
      ),
    );
  }
}

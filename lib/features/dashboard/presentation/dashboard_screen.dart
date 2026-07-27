import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/haptics.dart';
import '../../../core/config/theme.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/calendar_day_button.dart';
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/gradient_bars.dart';
import '../../../core/widgets/rounded_icon_tile.dart';
import '../../../core/widgets/segment_pills.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/extensions/format.dart';
import '../../../shared/providers/branch_scroll_provider.dart';
import '../../analytics/domain/analytics.dart';
import '../../analytics/presentation/analytics_controller.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../../transactions/presentation/sales_providers.dart';
import '../../transactions/presentation/transaction_confirmation_sheet.dart';
import 'receivables_card.dart';
import 'revenue_hero.dart';
import 'summary_breakdown_sheet.dart';

/// Home dashboard: greeting header, period pills, a 2×2 metric grid, the weekly
/// sales chart, a top performer card, and a low-stock list. All figures come
/// from Postgres RPCs / live product stream.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  AnalyticsPeriod _period = AnalyticsPeriod.today;

  // Period pills shown on the dashboard (the summary RPC also supports "all").
  static const _periods = [
    AnalyticsPeriod.today,
    AnalyticsPeriod.week,
    AnalyticsPeriod.month,
  ];

  /// Placeholder notifications surface. // MEMBER C owns the real one (push
  /// alerts, low-stock and sale events); this keeps the bell honest until then.
  static void _showNotificationsSheet(BuildContext context) {
    AppHaptics.tap();
    final theme = Theme.of(context);
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 48,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(l10n.dashboard_notificationsCaughtUp, style: theme.textTheme.titleMedium),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final shop = ref.watch(myShopProvider).value;
    final currency = shop?.currency ?? 'USD';
    final dateLabel = DateFormat('EEE, d MMM').format(DateTime.now());

    final selectedDay = ref.watch(selectedDayProvider);
    final summaryAsync = selectedDay != null
        ? ref.watch(daySummaryProvider(selectedDay))
        : ref.watch(summaryProvider(_period));
    final seriesAsync = ref.watch(seriesProvider(ChartBucket.daily));
    final lowStock =
        (ref.watch(productsStreamProvider).value ?? const <Product>[])
            .where((p) => p.isLowStock)
            .toList();

    return Scaffold(
      floatingActionButton: _SellFab(
        onTap: () {
          AppHaptics.tap();
          // Sale entry: jump to the Items tab, where the product → detail →
          // Add-to-cart flow lives. (A product-agnostic quick-sale picker is
          // future work — see the dashboard redesign spec.)
          context.go('/inventory');
        },
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            AppHaptics.tap();
            ref.invalidate(summaryProvider);
            ref.invalidate(seriesProvider);
          },
          child: ListView(
            controller: ref.watch(branchScrollControllerProvider(0)),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // Greeting header
              Entrance(
                index: 0,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            shop?.name ?? l10n.dashboard_yourShop,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    _HeaderIcon(
                      icon: Icons.notifications_none_rounded,
                      // MEMBER C: replace this placeholder with the real
                      // notifications surface (push alerts, low-stock/sale
                      // events). No dot until there's a real unread signal.
                      onTap: () => _showNotificationsSheet(context),
                    ),
                    const SizedBox(width: 8),
                    // Permanent door to the customer credit (khata) ledger. The
                    // receivables card below is hidden when nobody owes money, so
                    // this header icon is the always-present entry point.
                    _HeaderIcon(
                      icon: Icons.people_alt_outlined,
                      onTap: () => context.push(AppRoutes.customers),
                    ),
                    const SizedBox(width: 8),
                    _HeaderIcon(
                      icon: Icons.settings_outlined,
                      onTap: () => context.push('/settings'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Entrance(
                index: 1,
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentPills<AnalyticsPeriod>(
                        values: _periods,
                        selected: _period,
                        labelOf: (p) => periodLabel(l10n, p),
                        onChanged: (p) {
                          setState(() => _period = p);
                          // Period and day-mode are mutually exclusive.
                          ref.read(selectedDayProvider.notifier).set(null);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    CalendarDayButton(
                      selectedDay: selectedDay,
                      firstDate: ref.watch(earliestSaleDateProvider).value,
                      onPick: (day) =>
                          ref.read(selectedDayProvider.notifier).set(day),
                    ),
                  ],
                ),
              ),
              if (selectedDay != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: DayFilterChip(
                    label: DateFormat('EEE, d MMM').format(selectedDay),
                    onClear: () {
                      AppHaptics.tap();
                      ref.read(selectedDayProvider.notifier).set(null);
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              summaryAsync.when(
                loading: () => const _SummarySkeleton(),
                error: (_, _) => _ErrorText(l10n.dashboard_couldNotLoadSummary),
                data: (s) {
                  final margin = s.revenue > 0
                      ? s.profit / s.revenue * 100
                      : 0.0;
                  final isDay = selectedDay != null;
                  // Daily delta is only meaningful for Today; never in day-mode.
                  final delta = (!isDay && _period == AnalyticsPeriod.today)
                      ? _revenueDelta(seriesAsync.value)
                      : null;
                  final label = isDay
                      ? DateFormat('EEE, d MMM').format(selectedDay)
                      : periodLabel(l10n, _period);
                  return Entrance(
                    index: 2,
                    child: RevenueHero(
                      revenue: s.revenue,
                      profit: s.profit,
                      marginPercent: margin,
                      unitsSold: s.unitsSold,
                      currency: currency,
                      periodWord: label,
                      deltaPercent: delta,
                      showDeltaSuffix: !isDay && _period == AnalyticsPeriod.today,
                      onTap: () => showSummaryBreakdownSheet(
                        context,
                        summary: s,
                        period: _period,
                        currency: currency,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              const Entrance(index: 3, child: ReceivablesCard()),
              Entrance(
                index: 4,
                child: _WeeklySalesCard(
                  seriesAsync: seriesAsync,
                  currency: currency,
                ),
              ),
              Entrance(index: 5, child: _TopPerformer(currency: currency)),
              const SizedBox(height: 16),
              Entrance(
                index: 6,
                child: _LowStockCard(products: lowStock, currency: currency),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Revenue change of the most recent day vs the prior day, in percent, or null
  /// when there isn't enough data / the prior day was zero.
  double? _revenueDelta(List<SalesPoint>? points) {
    if (points == null || points.length < 2) return null;
    final last = points[points.length - 1].revenue;
    final prev = points[points.length - 2].revenue;
    if (prev <= 0) return null;
    return (last - prev) / prev * 100;
  }
}

/// Compact "Sell" action pill. Deliberately lighter-weight than a stock
/// [FloatingActionButton.extended] (which read as oversized against the cards),
/// while keeping the brand fill and the +/label affordance for discoverability.
class _SellFab extends StatelessWidget {
  const _SellFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.primary,
      borderRadius: BorderRadius.circular(14),
      elevation: 3,
      shadowColor: theme.colorScheme.primary.withValues(alpha: 0.35),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_rounded,
                size: 18,
                color: theme.colorScheme.onPrimary,
              ),
              const SizedBox(width: 6),
              Text(
                context.l10n.common_sell,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small circular header button with a hairline border (theme/notification).
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          shape: BoxShape.circle,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
      ),
    );
  }
}

class _WeeklySalesCard extends StatelessWidget {
  const _WeeklySalesCard({required this.seriesAsync, required this.currency});

  final AsyncValue<List<SalesPoint>> seriesAsync;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: seriesAsync.when(
          loading: () => const SizedBox(
            height: 180,
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (_, _) => SizedBox(
            height: 180,
            child: Center(child: Text(context.l10n.dashboard_couldNotLoadSales)),
          ),
          data: (points) {
            final values = [for (final p in points) p.revenue];
            final total = values.fold<double>(0, (a, b) => a + b);
            final peak = values.isEmpty
                ? -1
                : values.indexOf(values.reduce((a, b) => a > b ? a : b));
            final peakLabel = (peak >= 0 && values[peak] > 0)
                ? DateFormat('E').format(points[peak].bucket)
                : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.dashboard_salesLast7,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            Money.format(total, currencyCode: currency),
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (peakLabel != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme
                              .extension<AppColors>()!
                              .positive
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          context.l10n.dashboard_bestDay(peakLabel),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.extension<AppColors>()!.positive,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                GradientBars(
                  values: values,
                  labels: [
                    for (final p in points) weekdayBarLabel(locale, p.bucket),
                  ],
                  highlight: peak >= 0 ? peak : null,
                  height: 150,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TopPerformer extends ConsumerWidget {
  const _TopPerformer({required this.currency});

  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final best = ref.watch(bestSellersProvider).value;
    final top = (best != null && best.isNotEmpty && best.first.units > 0)
        ? best.first
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.dashboard_topPerformer,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        if (top == null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.dashboard_noSalesYet,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  RoundedTextTile(
                    text: top.name.isNotEmpty ? top.name[0].toUpperCase() : '?',
                    size: 44,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          top.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.l10n.dashboard_soldRevenue(
                            Qty.format(top.units),
                            Money.format(top.revenue, currencyCode: currency),
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      context.l10n.dashboard_mvpBadge,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

}

class _LowStockCard extends StatelessWidget {
  const _LowStockCard({required this.products, required this.currency});

  final List<Product> products;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: colors.warning,
                ),
                const SizedBox(width: 6),
                Text(
                  context.l10n.dashboard_lowStock,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.go('/inventory'),
                  child: Text(context.l10n.dashboard_viewAll),
                ),
              ],
            ),
            if (products.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
                child: Text(
                  context.l10n.dashboard_fullyStocked,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final p in products.take(4))
                _LowStockRow(product: p, currency: currency),
          ],
        ),
      ),
    );
  }
}

class _LowStockRow extends StatelessWidget {
  const _LowStockRow({required this.product, required this.currency});

  final Product product;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final qty = product.quantity == product.quantity.roundToDouble()
        ? product.quantity.toStringAsFixed(0)
        : product.quantity.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          RoundedTextTile(
            text: product.name.isNotEmpty ? product.name[0].toUpperCase() : '?',
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.dashboard_leftReorder(qty),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.negative,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: () => showRestockSheet(context, product: product),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 38),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(context.l10n.common_restock),
          ),
        ],
      ),
    );
  }
}

/// Placeholder that mirrors the revenue hero so the layout doesn't jump when the
/// real figures arrive.
class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    return const Skeleton(height: 150, radius: 18);
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 80, child: Center(child: Text(message)));
  }
}


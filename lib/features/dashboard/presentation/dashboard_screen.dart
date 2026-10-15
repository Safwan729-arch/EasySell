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
import '../../expiry/presentation/expiry_alerts_card.dart';
import '../../expiry/presentation/expiry_providers.dart';
import '../../restock/presentation/restock_card.dart';
import '../../transactions/presentation/sales_providers.dart';
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
    final alertCount = ref.watch(expiryAlertsProvider).length;

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
            // Bottom padding clears the floating _SellFab, which otherwise sits
            // on top of the last card's trailing action once scrolled to the
            // end. 96 matches the reserve used by History and Customers, the
            // other screens with something floating over their list.
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
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
                    // Expiry alerts (expiry spec §5). // MEMBER C: other
                    // notification kinds (sales, low stock) can join this
                    // screen later.
                    Badge.count(
                      count: alertCount,
                      isLabelVisible: alertCount > 0,
                      child: _HeaderIcon(
                        icon: Icons.notifications_none_rounded,
                        onTap: () {
                          AppHaptics.tap();
                          context.push(AppRoutes.alerts);
                        },
                      ),
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
                      showDeltaSuffix:
                          !isDay && _period == AnalyticsPeriod.today,
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
              // Cards carry `margin: EdgeInsets.zero` (see cardTheme), so every
              // gap in this column is explicit. _TopPerformer leads with a bare
              // section label rather than a Card, so without this it sits flush
              // on the chart card's border above it.
              const SizedBox(height: 20),
              Entrance(index: 5, child: _TopPerformer(currency: currency)),
              const SizedBox(height: 16),
              // Restock soon also covers products at their reorder level: the
              // separate Low stock card said "fully stocked" right under
              // "4 items to restock" (merged 2026-10-15, restock spec §10).
              const Entrance(index: 6, child: RestockSoonCard()),
              const Entrance(index: 7, child: ExpiryAlertsCard()),
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
            child: Center(
              child: Text(context.l10n.dashboard_couldNotLoadSales),
            ),
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

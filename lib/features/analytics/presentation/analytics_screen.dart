import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/haptics.dart';
import '../../../core/config/motion.dart';
import '../../../core/widgets/calendar_day_button.dart';
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/extensions/format.dart';
import '../../../shared/providers/branch_scroll_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../transactions/presentation/sales_providers.dart';
import '../domain/analytics.dart';
import 'analytics_controller.dart';
import 'donut_chart.dart';

/// Distinct, ordered hues for the category donut, assigned by slice rank so two
/// slices never collide (the earlier per-name hashing could). Leads with the
/// brand blue and stays legible on both light and dark surfaces.
const _donutPalette = <Color>[
  Color(0xFF2563EB), // blue (brand)
  Color(0xFFEA580C), // orange
  Color(0xFF16A34A), // green
  Color(0xFF7C3AED), // purple
  Color(0xFF0D9488), // teal
  Color(0xFFDB2777), // pink
];

Color _donutColor(int index) => _donutPalette[index % _donutPalette.length];

/// Reports — an editorial business-review surface. Two cards: a category-mix
/// donut and a "Biggest wins" leaderboard. The Week/Month/All selector lives
/// under the donut and scopes both ([reportPeriodProvider]); switching it
/// cross-fades the content.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            AppHaptics.tap();
            ref.invalidate(allSalesProvider);
          },
          child: ListView(
            controller: ref.watch(branchScrollControllerProvider(2)),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            children: [
              Text(
                'BUSINESS REPORT',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Reports',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 16),
              const _CategoryCard(),
              const SizedBox(height: 16),
              const _BestSellersCard(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small uppercase section label that opens every Reports card.
class _Kicker extends StatelessWidget {
  const _Kicker(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text.toUpperCase(),
      style: theme.textTheme.labelMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.w800,
        letterSpacing: 1.1,
      ),
    );
  }
}

/// The base card surface for Reports — roomier padding than Home.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    );
  }
}

// ---- Category split (donut) -----------------------------------------------

class _CategoryCard extends ConsumerStatefulWidget {
  const _CategoryCard();

  @override
  ConsumerState<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends ConsumerState<_CategoryCard> {
  // Last resolved data, kept so a period switch shows the previous donut while
  // the new period reloads — never a flash of the empty state.
  List<CategorySlice>? _last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(reportCategorySplitProvider);
    if (async.hasValue) _last = async.value;
    final data = async.value ?? _last;

    final Widget body;
    if (data == null) {
      // Never loaded yet — placeholder, not the empty hint.
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Skeleton(height: 232, radius: 16),
      );
    } else if (data.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          'No sales in this period yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    } else {
      // Persistent (no per-period Key) so the PieChart morphs between values.
      body = _DonutBlock(slices: data.take(6).toList());
    }

    return _ReportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Kicker('Where revenue comes from'),
          const SizedBox(height: 8),
          body,
          const SizedBox(height: 16),
          const _PeriodControl(),
        ],
      ),
    );
  }
}

/// Centered donut + a full-width legend below it (so long category names fit).
class _DonutBlock extends StatelessWidget {
  const _DonutBlock({required this.slices});
  final List<CategorySlice> slices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (slices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          'No sales in this period yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final topPct = (slices.first.fraction * 100).round();
    return Column(
      children: [
        const SizedBox(height: 6),
        Center(
          child: DonutChart(
            slices: [
              for (var i = 0; i < slices.length; i++)
                DonutSlice(value: slices[i].fraction, color: _donutColor(i)),
            ],
            centerLabel: '$topPct%',
            centerSub: 'top share',
          ),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < slices.length; i++)
          _LegendRow(
            name: slices[i].name,
            percent: (slices[i].fraction * 100).round(),
            color: _donutColor(i),
          ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.name,
    required this.percent,
    required this.color,
  });

  final String name;
  final int percent;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            '$percent%',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

/// The period control under the donut: Today / Week / Month underline tabs plus a
/// calendar button for drilling into a single past day — mirroring the Home tab.
/// Scopes both the category split and the leaderboard ([reportPeriodProvider] /
/// [reportSelectedDayProvider]). When a day is active, no pill is highlighted and
/// a dismissible chip appears; tapping a pill clears the day.
class _PeriodControl extends ConsumerWidget {
  const _PeriodControl();

  static const _periods = [
    AnalyticsPeriod.today,
    AnalyticsPeriod.week,
    AnalyticsPeriod.month,
  ];

  static String _word(AnalyticsPeriod p) => switch (p) {
    AnalyticsPeriod.today => 'Today',
    AnalyticsPeriod.week => 'Week',
    AnalyticsPeriod.month => 'Month',
    AnalyticsPeriod.all => 'All',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final period = ref.watch(reportPeriodProvider);
    final day = ref.watch(reportSelectedDayProvider);
    return Column(
      children: [
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Center(
                child: _UnderlineTabs<AnalyticsPeriod>(
                  values: _periods,
                  // Day-mode overrides the period, so no pill is highlighted.
                  selected: day == null ? period : null,
                  labelOf: _word,
                  gap: 22,
                  onChanged: (p) {
                    ref.read(reportSelectedDayProvider.notifier).set(null);
                    ref.read(reportPeriodProvider.notifier).set(p);
                  },
                ),
              ),
            ),
            CalendarDayButton(
              selectedDay: day,
              size: 34,
              firstDate: ref.watch(earliestSaleDateProvider).value,
              onPick: (d) =>
                  ref.read(reportSelectedDayProvider.notifier).set(d),
            ),
          ],
        ),
        if (day != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: DayFilterChip(
              label: DateFormat('EEE, d MMM').format(day),
              onClear: () {
                AppHaptics.tap();
                ref.read(reportSelectedDayProvider.notifier).set(null);
              },
            ),
          ),
        ],
      ],
    );
  }
}

// ---- Best sellers (leaderboard) --------------------------------------------

class _BestSellersCard extends ConsumerStatefulWidget {
  const _BestSellersCard();

  @override
  ConsumerState<_BestSellersCard> createState() => _BestSellersCardState();
}

class _BestSellersCardState extends ConsumerState<_BestSellersCard> {
  // Last resolved list, kept so a period switch holds the previous leaderboard
  // while the new period reloads — never a flash of the empty state.
  List<BestSeller>? _last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final period = ref.watch(reportPeriodProvider);
    final day = ref.watch(reportSelectedDayProvider);
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final async = ref.watch(reportBestSellersProvider);
    if (async.hasValue) _last = async.value;
    final data = async.value ?? _last;
    final top = data?.take(4).toList();

    final Widget body;
    if (top == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Skeleton(height: 184, radius: 16),
      );
    } else if (top.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No sales in this period yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    } else {
      // Persistent (no per-period Key) so each share bar glides to its new width.
      body = _WinsBody(top: top, period: period, day: day, currency: currency);
    }

    return _ReportCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Kicker('Biggest wins'),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }
}

class _WinsBody extends StatelessWidget {
  const _WinsBody({
    required this.top,
    required this.period,
    required this.day,
    required this.currency,
  });

  final List<BestSeller> top;
  final AnalyticsPeriod period;
  final DateTime? day;
  final String currency;

  /// The trailing phrase in "X is carrying …". A drilled-into day wins over the
  /// running period, matching how the control scopes the data.
  static String _scopeWord(AnalyticsPeriod p, DateTime? day) {
    if (day != null) return 'on ${DateFormat('d MMM').format(day)}';
    return switch (p) {
      AnalyticsPeriod.week => 'this week',
      AnalyticsPeriod.month => 'this month',
      AnalyticsPeriod.all => 'all time',
      AnalyticsPeriod.today => 'today',
    };
  }


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (top.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No sales in this period yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final leaderUnits = top.first.units;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${top.first.name} is carrying ${_scopeWord(period, day)}.',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < top.length; i++)
          Entrance(
            index: i,
            child: _LeaderRow(
              rank: i + 1,
              name: top[i].name,
              units: '${Qty.format(top[i].units)} units',
              revenue: Money.compact(top[i].revenue, currencyCode: currency),
              fraction: leaderUnits <= 0 ? 0 : top[i].units / leaderUnits,
            ),
          ),
      ],
    );
  }
}

class _LeaderRow extends StatelessWidget {
  const _LeaderRow({
    required this.rank,
    required this.name,
    required this.units,
    required this.revenue,
    required this.fraction,
  });

  final int rank;
  final String name;
  final String units;
  final String revenue;
  final double fraction;

  // Medal tints for the podium; rank 4+ falls back to the brand color.
  static const _gold = Color(0xFFD9A300);
  static const _silver = Color(0xFF8E97A8);
  static const _bronze = Color(0xFFB45309);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final badge = switch (rank) {
      1 => _gold,
      2 => _silver,
      3 => _bronze,
      _ => scheme.primary,
    };
    final onBadge =
        ThemeData.estimateBrightnessForColor(badge) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final isFirst = rank == 1;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isFirst ? badge.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: badge, shape: BoxShape.circle),
            child: Text(
              '$rank',
              style: theme.textTheme.labelLarge?.copyWith(
                color: onBadge,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _ShareBar(fraction: fraction, color: badge),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                units,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                revenue,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A thin "share of the leader" bar that fills in when it appears.
class _ShareBar extends StatelessWidget {
  const _ShareBar({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.surfaceContainerHighest;
    final target = fraction.clamp(0.0, 1.0);

    Widget bar(double value) => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 6,
        backgroundColor: track,
        valueColor: AlwaysStoppedAnimation(color),
      ),
    );

    if (AppMotion.reduced(context)) return bar(target);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: target),
      duration: AppMotion.count,
      curve: AppMotion.easeOut,
      builder: (_, value, _) => bar(value),
    );
  }
}

// ---- Shared controls -------------------------------------------------------

/// Underline text tabs (the Week/Month/All period selector). The active tab is
/// inked with a brand underline.
class _UnderlineTabs<T> extends StatelessWidget {
  const _UnderlineTabs({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
    this.gap = 18,
  });

  final List<T> values;

  /// The highlighted value, or null when none should be highlighted (e.g. the
  /// Reports tab is in calendar day-mode).
  final T? selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < values.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          GestureDetector(
            onTap: () {
              if (values[i] != selected) {
                AppHaptics.tap();
                onChanged(values[i]);
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  labelOf(values[i]),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: values[i] == selected
                        ? theme.colorScheme.onSurface
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                AnimatedContainer(
                  duration: AppMotion.fast,
                  curve: AppMotion.easeOut,
                  height: 2.5,
                  width: 20,
                  decoration: BoxDecoration(
                    color: values[i] == selected
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

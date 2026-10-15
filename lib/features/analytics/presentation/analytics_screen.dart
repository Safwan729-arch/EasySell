import 'package:ai_shopkeeper/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/config/haptics.dart';
import '../../../core/config/motion.dart';
import '../../../core/config/theme.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/calendar_day_button.dart';
import '../../../core/widgets/entrance.dart';
import '../../../core/widgets/section_bits.dart';
import '../../../core/widgets/segment_pills.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../shared/extensions/format.dart';
import '../../../shared/providers/branch_scroll_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../transactions/presentation/sales_providers.dart';
import '../domain/analytics.dart';
import 'analytics_controller.dart';
import 'donut_chart.dart';

/// Distinct, ordered hues for the category donut, assigned by slice rank so two
/// slices never collide (the earlier per-name hashing could). The first three
/// are the design's chart colours (§3.4); dark uses slightly brighter shades.
const _donutPalette = <Color>[
  Color(0xFF277AFD), // blue
  Color(0xFFFE8022), // orange
  Color(0xFF03A785), // green
  Color(0xFF7B4DFA), // violet
  Color(0xFF0D9488), // teal
  Color(0xFFDB2777), // pink
];
const _donutPaletteDark = <Color>[
  Color(0xFF3D86FF),
  Color(0xFFFF7A1A),
  Color(0xFF1FB46A),
  Color(0xFF8B5CF6),
  Color(0xFF14B8A6),
  Color(0xFFEC4899),
];

Color _donutColor(BuildContext context, int index) {
  final palette = Theme.of(context).brightness == Brightness.dark
      ? _donutPaletteDark
      : _donutPalette;
  return palette[index % palette.length];
}

/// Reports — an editorial business-review surface. Two cards: a category-mix
/// donut and a "Biggest wins" leaderboard. The Week/Month/All selector lives
/// under the donut and scopes both ([reportPeriodProvider]); switching it
/// cross-fades the content.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

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
              Eyebrow(l10n.analytics_kicker),
              const SizedBox(height: 2),
              Text(
                l10n.analytics_title,
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 18),
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

/// The base card surface for Reports.
class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => AppCard(child: child);
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
          context.l10n.analytics_noSalesPeriod,
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
          Eyebrow(context.l10n.analytics_revenueSource),
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
    final l10n = context.l10n;
    if (slices.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
          l10n.analytics_noSalesPeriod,
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
                DonutSlice(
                  value: slices[i].fraction,
                  color: _donutColor(context, i),
                ),
            ],
            centerLabel: '${Qty.format(topPct)}%',
            centerSub: l10n.analytics_topShare,
          ),
        ),
        const SizedBox(height: 18),
        for (var i = 0; i < slices.length; i++)
          _LegendRow(
            name: slices[i].name,
            percent: (slices[i].fraction * 100).round(),
            color: _donutColor(context, i),
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
    final colors = theme.extension<AppColors>()!;
    final isDark = theme.brightness == Brightness.dark;
    // Light: each legend line is a soft tinted row. Dark: plain lines.
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: isDark ? 2 : 14, vertical: 10),
      decoration: isDark
          ? null
          : BoxDecoration(
              color: colors.muted,
              borderRadius: BorderRadius.circular(16),
            ),
      child: Row(
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            '${Qty.format(percent)}%',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The period control under the donut: Today / Week / Month pills plus a
/// calendar button for drilling into a single past day — the same control as
/// the Home tab (pills in both themes; design decision 1 ruled out the dark
/// mockup's underline tabs as a second widget for one screen).
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final period = ref.watch(reportPeriodProvider);
    final day = ref.watch(reportSelectedDayProvider);
    return Column(
      children: [
        Divider(height: 1, color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: SegmentPills<AnalyticsPeriod>(
                expand: true,
                values: _periods,
                // Day-mode overrides the period, so no pill is highlighted.
                selected: day == null ? period : null,
                labelOf: (p) => periodLabel(l10n, p),
                onChanged: (p) {
                  if (p == period && day == null) return;
                  AppHaptics.tap();
                  ref.read(reportSelectedDayProvider.notifier).set(null);
                  ref.read(reportPeriodProvider.notifier).set(p);
                },
              ),
            ),
            const SizedBox(width: 8),
            CalendarDayButton(
              selectedDay: day,
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
          context.l10n.analytics_noSalesPeriod,
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
          Eyebrow(context.l10n.analytics_biggestWins),
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
  static String _scopeWord(
    AppLocalizations l10n,
    AnalyticsPeriod p,
    DateTime? day,
  ) {
    if (day != null) {
      return l10n.analytics_scopeDay(DateFormat('d MMM').format(day));
    }
    return switch (p) {
      AnalyticsPeriod.week => l10n.analytics_scopeWeek,
      AnalyticsPeriod.month => l10n.analytics_scopeMonth,
      AnalyticsPeriod.all => l10n.analytics_scopeAll,
      AnalyticsPeriod.today => l10n.analytics_scopeToday,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    if (top.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          l10n.analytics_noSalesPeriod,
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
          l10n.analytics_carrying(
            top.first.name,
            _scopeWord(l10n, period, day),
          ),
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < top.length; i++)
          Entrance(
            index: i,
            child: _LeaderRow(
              rank: i + 1,
              name: top[i].name,
              units: l10n.analytics_units(Qty.format(top[i].units)),
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

  // Rank badges (design §3.4): gold, silver, bronze, then blue.
  static const _gold = Color(0xFFF6B71A);
  static const _silver = Color(0xFF8E99BF);
  static const _bronze = Color(0xFFC1590E);
  static const _blue = Color(0xFF256FFE);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = theme.extension<AppColors>()!;
    final isDark = theme.brightness == Brightness.dark;
    final badge = switch (rank) {
      1 => _gold,
      2 => _silver,
      3 => _bronze,
      _ => _blue,
    };
    final isFirst = rank == 1;

    // Light: the winner's row is pale gold, others a soft blue-grey. Dark: all
    // rows are outlined glass.
    final decoration = isDark
        ? colors.rowDecoration()
        : BoxDecoration(
            color: isFirst ? const Color(0xFFFEF9EC) : const Color(0xFFF4F6FD),
            borderRadius: BorderRadius.circular(16),
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 12, 16, 12),
      decoration: decoration,
      child: Row(
        children: [
          // A glossy circle: the badge colour with a lighter top-left.
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.4, -0.5),
                radius: 0.9,
                colors: [Color.lerp(badge, Colors.white, 0.28)!, badge],
              ),
              boxShadow: [
                BoxShadow(
                  color: badge.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Text(
              '$rank',
              style: theme.textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
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
                    fontSize: 17,
                    fontWeight: FontWeight.w500,
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
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                revenue,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontSize: 15,
                  color: scheme.onSurfaceVariant,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final track = isDark ? const Color(0xFF25304F) : const Color(0xFFF4EAE3);
    final target = fraction.clamp(0.0, 1.0);

    Widget bar(double value) => ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: LinearProgressIndicator(
        value: value,
        minHeight: 8,
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

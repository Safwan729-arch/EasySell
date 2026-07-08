import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/category_controller.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/presentation/history_screen.dart';
import '../data/analytics_repository.dart';
import '../domain/analytics.dart';

/// Aggregated totals for a period (RPC-backed). Refetches when a sale/restock
/// bumps [dataRefreshProvider].
final summaryProvider = FutureProvider.autoDispose
    .family<DashboardSummary, AnalyticsPeriod>((ref, period) async {
      ref.watch(dataRefreshProvider);
      final shop = ref.watch(myShopProvider).value;
      if (shop == null) return DashboardSummary.empty;
      final result = await ref
          .watch(analyticsRepositoryProvider)
          .getSummary(shop.id, period);
      return result.when(success: (s) => s, failure: (f) => throw f);
    });

/// The day the user has drilled into on the dashboard, or null for the normal
/// period view. Selecting a period pill (or the chip's clear) resets this to null.
class SelectedDayController extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void set(DateTime? day) => state = day;
}

final selectedDayProvider =
    NotifierProvider<SelectedDayController, DateTime?>(
      SelectedDayController.new,
    );

/// One calendar day's summary, RPC-backed so aggregation happens server-side and
/// the payload stays small regardless of that day's transaction count (CLAUDE.md
/// §5). [day] must be date-only (midnight local). Refetches when a sale/restock
/// bumps [dataRefreshProvider].
final daySummaryProvider = FutureProvider.autoDispose
    .family<DashboardSummary, DateTime>((ref, day) async {
      ref.watch(dataRefreshProvider);
      final shop = ref.watch(myShopProvider).value;
      if (shop == null) return DashboardSummary.empty;
      final result = await ref
          .watch(analyticsRepositoryProvider)
          .getSummary(shop.id, AnalyticsPeriod.all, day: day);
      return result.when(success: (s) => s, failure: (f) => throw f);
    });

/// Revenue/profit time series for the chart, by bucket granularity.
final seriesProvider = FutureProvider.autoDispose
    .family<List<SalesPoint>, ChartBucket>((ref, bucket) async {
      ref.watch(dataRefreshProvider);
      final shop = ref.watch(myShopProvider).value;
      if (shop == null) return const <SalesPoint>[];
      final result = await ref
          .watch(analyticsRepositoryProvider)
          .getSeries(shop.id, bucket);
      return result.when(success: (s) => s, failure: (f) => throw f);
    });

/// A product ranked by units sold, derived client-side from recent sales joined
/// to the live product list (small data volumes — see CLAUDE.md §5). Used by the
/// dashboard "Top performer" and the Reports "Best sellers" / category split.
class BestSeller {
  const BestSeller({
    required this.productId,
    required this.name,
    required this.categoryId,
    required this.units,
    required this.revenue,
  });

  final String productId;
  final String name;
  final String? categoryId;
  final double units;
  final double revenue;
}

/// Aggregates [sales] into best sellers (desc by units), resolving names and
/// categories against [products]. Shared by the unscoped dashboard provider and
/// the period-scoped Reports provider.
List<BestSeller> aggregateBestSellers(
  List<Transaction> sales,
  List<Product> products,
) {
  final byId = {for (final p in products) p.id: p};
  final units = <String, double>{};
  final revenue = <String, double>{};
  for (final s in sales) {
    units[s.productId] = (units[s.productId] ?? 0) + s.quantity;
    revenue[s.productId] = (revenue[s.productId] ?? 0) + s.revenue;
  }
  return units.keys.map((id) {
    final p = byId[id];
    return BestSeller(
      productId: id,
      name: p?.name ?? 'Unknown',
      categoryId: p?.categoryId,
      units: units[id]!,
      revenue: revenue[id]!,
    );
  }).toList()..sort((a, b) => b.units.compareTo(a.units));
}

/// Best sellers (desc by units) aggregated from the unscoped recent sales +
/// products. Powers the dashboard "Top performer".
final bestSellersProvider = Provider.autoDispose<AsyncValue<List<BestSeller>>>((
  ref,
) {
  final salesAsync = ref.watch(recentSalesProvider);
  final products = ref.watch(productsStreamProvider).value ?? const <Product>[];
  return salesAsync.whenData((sales) => aggregateBestSellers(sales, products));
});

// ---- Reports tab (period-scoped) ------------------------------------------

/// The Reports tab's selected period (Today / Week / Month), mirroring the Home
/// dashboard's pills. Persists while the app runs so returning to the tab keeps
/// the last view. Defaults to today.
class ReportPeriodController extends Notifier<AnalyticsPeriod> {
  @override
  AnalyticsPeriod build() => AnalyticsPeriod.today;

  void set(AnalyticsPeriod period) => state = period;
}

final reportPeriodProvider =
    NotifierProvider<ReportPeriodController, AnalyticsPeriod>(
      ReportPeriodController.new,
    );

/// The single past day the Reports tab has drilled into via the calendar, or null
/// for the running-period view. Independent from the dashboard's
/// [selectedDayProvider] — a day picked on one tab does not affect the other.
/// Selecting a period pill resets this to null (day and period are mutually
/// exclusive, exactly like the Home tab).
class ReportSelectedDayController extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void set(DateTime? day) => state = day;
}

final reportSelectedDayProvider =
    NotifierProvider<ReportSelectedDayController, DateTime?>(
      ReportSelectedDayController.new,
    );

/// The lower `created_at` bound for [period], mirroring `get_dashboard_summary`'s
/// `date_trunc` boundaries (week = start of ISO week / Monday, month = 1st of the
/// calendar month) so the Reports category split and best sellers line up with
/// the summary RPC. Returns null for `all` (no lower bound). [now] is injectable
/// for tests.
DateTime? periodSince(AnalyticsPeriod period, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final midnight = DateTime(n.year, n.month, n.day);
  switch (period) {
    case AnalyticsPeriod.today:
      return midnight;
    case AnalyticsPeriod.week:
      // weekday: Mon = 1 … Sun = 7 → back up to Monday.
      return midnight.subtract(Duration(days: midnight.weekday - 1));
    case AnalyticsPeriod.month:
      return DateTime(n.year, n.month, 1);
    case AnalyticsPeriod.all:
      return null;
  }
}

/// Every recent sale for the shop (newest first, unscoped), fetched ONCE and
/// cached while watched. The Reports category split and best sellers filter this
/// list client-side by the selected period/day ([salesInScope]) — so switching
/// Today / Week / Month / a calendar day is an instant synchronous recompute with
/// no network round-trip and no refetch-on-switch-back. Capped at a generous
/// limit (tiny MVP volumes, see CLAUDE.md §5). Refetches only when a sale/restock
/// bumps [dataRefreshProvider].
final allSalesProvider = FutureProvider.autoDispose<List<Transaction>>((
  ref,
) async {
  ref.watch(dataRefreshProvider);
  final shopId = ref.watch(myShopProvider).value?.id;
  if (shopId == null) return const <Transaction>[];
  final result = await ref
      .read(transactionRepositoryProvider)
      .recentSales(shopId: shopId, limit: 1000);
  return result.when(success: (l) => l, failure: (f) => throw f);
});

/// Filters already-fetched [sales] to the Reports scope: a single [day] when
/// non-null (that calendar day, local midnight-to-midnight), otherwise [period]
/// bounded by [periodSince]. Pure and synchronous — the cost of switching filters
/// is a single list pass, not a network call. Day and period are mutually
/// exclusive: a non-null [day] wins. [now] is injectable for tests.
List<Transaction> salesInScope(
  List<Transaction> sales, {
  required AnalyticsPeriod period,
  DateTime? day,
  DateTime? now,
}) {
  if (day != null) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return [
      for (final s in sales)
        if (s.createdAt != null &&
            !s.createdAt!.isBefore(start) &&
            s.createdAt!.isBefore(end))
          s,
    ];
  }
  final since = periodSince(period, now: now);
  if (since == null) return sales; // all-time: no lower bound
  return [
    for (final s in sales)
      if (s.createdAt != null && !s.createdAt!.isBefore(since)) s,
  ];
}

/// Best sellers for the Reports tab, scoped to the current period/day. Derives
/// from the cached [allSalesProvider] so period switches never hit the network.
final reportBestSellersProvider =
    Provider.autoDispose<AsyncValue<List<BestSeller>>>((ref) {
      final period = ref.watch(reportPeriodProvider);
      final day = ref.watch(reportSelectedDayProvider);
      final salesAsync = ref.watch(allSalesProvider);
      final products =
          ref.watch(productsStreamProvider).value ?? const <Product>[];
      return salesAsync.whenData(
        (all) => aggregateBestSellers(
          salesInScope(all, period: period, day: day),
          products,
        ),
      );
    });

/// One category's share of period revenue, for the Reports donut. Color is
/// assigned in the widget (via `tileColorFor`) to keep this layer presentation-free.
class CategorySlice {
  const CategorySlice({
    required this.name,
    required this.revenue,
    required this.fraction,
  });

  final String name;
  final double revenue;

  /// Share of total period revenue, 0..1.
  final double fraction;
}

/// Revenue-by-category split for the Reports tab, scoped to the current
/// period/day, desc by revenue. Derives from the cached [allSalesProvider] so
/// period switches recompute synchronously. Empty when there are no sales.
final reportCategorySplitProvider =
    Provider.autoDispose<AsyncValue<List<CategorySlice>>>((ref) {
      final period = ref.watch(reportPeriodProvider);
      final day = ref.watch(reportSelectedDayProvider);
      final salesAsync = ref.watch(allSalesProvider);
      final products =
          ref.watch(productsStreamProvider).value ?? const <Product>[];
      final categories = ref.watch(usedCategoriesProvider);
      final nameById = {for (final c in categories) c.id: c.name};
      final catOf = {for (final p in products) p.id: p.categoryId};
      return salesAsync.whenData((all) {
        final sales = salesInScope(all, period: period, day: day);
        final byCat = <String, double>{};
        for (final s in sales) {
          final catId = catOf[s.productId];
          final name = catId == null
              ? 'Uncategorized'
              : (nameById[catId] ?? '—');
          byCat[name] = (byCat[name] ?? 0) + s.revenue;
        }
        final total = byCat.values.fold<double>(0, (a, b) => a + b);
        if (total <= 0) return const <CategorySlice>[];
        final entries = byCat.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        return [
          for (final e in entries)
            CategorySlice(
              name: e.key,
              revenue: e.value,
              fraction: e.value / total,
            ),
        ];
      });
    });

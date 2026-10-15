import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/theme.dart';
import '../../../core/error/failure.dart';
import '../../../core/router/app_router.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/calendar_day_button.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/two_option_segment.dart';
import '../../../shared/extensions/format.dart';
import '../../../shared/providers/branch_scroll_provider.dart';
import '../../../shared/providers/refresh_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../inventory/domain/product.dart';
import '../../inventory/presentation/inventory_controller.dart';
import '../data/transaction_repository.dart';
import '../domain/transaction.dart';
import 'sales_providers.dart';

/// One row in Sales History: either a single ungrouped sale or every line
/// from one cart checkout, grouped by `sale_group_id`. Transactions with no
/// group id (manual/voice/single-scan sales, and every pre-cart historical
/// row) become their own singleton receipt, keyed by their own transaction id
/// so they never merge with another ungrouped sale.
class SaleReceipt {
  const SaleReceipt({required this.id, required this.lines});

  final String id;
  final List<Transaction> lines;

  DateTime? get createdAt => lines.first.createdAt;
  double get totalRevenue => lines.fold<double>(0, (sum, t) => sum + t.revenue);
  int get lineCount => lines.length;

  /// The discount the shopkeeper actually typed, recovered by summing the
  /// per-line shares `record_sale_cart` allocated.
  ///
  /// This is the only place that figure exists in the app. The database stores
  /// no receipt-level discount -- a receipt is just rows sharing a
  /// `sale_group_id` -- and the split is exact to the paisa precisely so this
  /// sum reproduces the original. Without it a 3-line sale with ৳7 off shows
  /// `−৳2.33` on one line's detail and the ৳7 appears nowhere.
  double get discountTotal =>
      lines.fold<double>(0, (sum, t) => sum + t.discountAmount);

  /// What the receipt came to before the discount.
  double get grossRevenue => totalRevenue + discountTotal;
}

/// Groups [sales] into receipts by `saleGroupId`, preserving each receipt's
/// first-seen order in [sales].
List<SaleReceipt> groupSalesIntoReceipts(List<Transaction> sales) {
  final byGroup = <String, List<Transaction>>{};
  final order = <String>[];
  for (final t in sales) {
    final key = t.saleGroupId ?? 'single-${t.id}';
    if (!byGroup.containsKey(key)) order.add(key);
    byGroup.putIfAbsent(key, () => []).add(t);
  }
  return [for (final key in order) SaleReceipt(id: key, lines: byGroup[key]!)];
}

/// Recent SALE transactions for the current shop, newest first. Re-fetches when
/// a sale/restock bumps [dataRefreshProvider].
final recentSalesProvider = FutureProvider.autoDispose<List<Transaction>>((
  ref,
) async {
  ref.watch(dataRefreshProvider);
  final shopId = ref.watch(myShopProvider).value?.id;
  if (shopId == null) return const [];
  final result = await ref
      .read(transactionRepositoryProvider)
      .recentSales(shopId: shopId);
  return result.when(success: (list) => list, failure: (f) => throw f);
});

/// How far back the table reaches. Filtered client-side over the fetched sales.
enum _Scope { today, week }

/// Which column the table is sorted by.
enum _SortKey { time, item, qty, amount }

/// Sales history as a dense, sortable table (Time · Item · Qty · Amount). Search
/// narrows by product name; the Today/Week/All control scopes the window; tapping
/// a column header sorts by it (tap again to flip direction). Built for the job
/// of *finding a specific sale*, primarily by amount.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  Timer? _debounce;

  _Scope _scope = _Scope.today;
  DateTime? _selectedDay;
  _SortKey _sortKey = _SortKey.time;
  bool _ascending = false; // newest-first by default

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Re-filters ~250ms after the last keystroke so a fast typist doesn't trigger
  /// a rebuild per character. The clear button bypasses this for an instant reset.
  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _query = value);
    });
  }

  /// Sensible initial direction per column: text sorts A→Z, everything numeric
  /// or time-based sorts high→low (newest / biggest / most first).
  bool _defaultAscending(_SortKey key) => key == _SortKey.item;

  void _onSort(_SortKey key) {
    setState(() {
      if (_sortKey == key) {
        _ascending = !_ascending;
      } else {
        _sortKey = key;
        _ascending = _defaultAscending(key);
      }
    });
  }

  bool _inScope(DateTime? createdAt) {
    if (_selectedDay != null) return true; // day-mode: list is already the day
    final now = DateTime.now();
    final local = (createdAt ?? now).toLocal();
    final startOfToday = DateTime(now.year, now.month, now.day);
    return switch (_scope) {
      _Scope.today => !local.isBefore(startOfToday),
      // Rolling 7 days (today plus the previous six).
      _Scope.week => !local.isBefore(
        startOfToday.subtract(const Duration(days: 6)),
      ),
    };
  }

  List<_ReceiptRow> _visibleRows(
    List<Transaction> all,
    Map<String, String> names,
  ) {
    final q = _query.trim().toLowerCase();
    final rows = <_ReceiptRow>[];
    for (final receipt in groupSalesIntoReceipts(all)) {
      if (!_inScope(receipt.createdAt)) continue;
      final row = _ReceiptRow(receipt: receipt, names: names);
      if (!row.matches(q)) continue;
      rows.add(row);
    }
    rows.sort((a, b) {
      final cmp = switch (_sortKey) {
        _SortKey.time => (a.receipt.createdAt ?? _epoch).compareTo(
          b.receipt.createdAt ?? _epoch,
        ),
        _SortKey.item => a.sortName.compareTo(b.sortName),
        _SortKey.qty => a.qtyValue.compareTo(b.qtyValue),
        _SortKey.amount => a.receipt.totalRevenue.compareTo(
          b.receipt.totalRevenue,
        ),
      };
      return _ascending ? cmp : -cmp;
    });
    return rows;
  }

  static final _epoch = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final day = _selectedDay;
    final salesAsync = day == null
        ? ref.watch(recentSalesProvider)
        : ref.watch(salesForDayProvider(day));
    final firstDate = ref.watch(earliestSaleDateProvider).value;
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';
    final products =
        ref.watch(productsStreamProvider).value ?? const <Product>[];
    final nameById = {for (final p in products) p.id: p.name};

    void refreshActive() {
      if (_selectedDay == null) {
        ref.invalidate(recentSalesProvider);
      } else {
        ref.invalidate(salesForDayProvider(_selectedDay!));
      }
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: salesAsync.when(
          loading: () => const _HistorySkeleton(),
          error: (e, _) => _ErrorState(
            message: e is Failure ? e.message : l10n.history_couldNotLoad,
            onRetry: refreshActive,
          ),
          data: (all) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                  child: Text(
                    l10n.history_title,
                    style: theme.textTheme.headlineLarge?.copyWith(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: l10n.history_search,
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _debounce?.cancel();
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _ScopeSelector(
                              scope: _scope,
                              dayActive: day != null,
                              onChanged: (s) => setState(() {
                                _scope = s;
                                _selectedDay = null;
                              }),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CalendarDayButton(
                            selectedDay: day,
                            firstDate: firstDate,
                            onPick: (picked) =>
                                setState(() => _selectedDay = picked),
                          ),
                        ],
                      ),
                      if (day != null) ...[
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: DayFilterChip(
                            label: DateFormat('EEE, d MMM y').format(day),
                            onClear: () => setState(() => _selectedDay = null),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: all.isEmpty
                      ? _EmptyState(
                          message: day == null
                              ? l10n.history_noSalesYet
                              : l10n.history_noSalesOnDay(
                                  DateFormat('EEE, d MMM y').format(day),
                                ),
                          showHint: day == null,
                        )
                      : _SalesTable(
                          rows: _visibleRows(all, nameById),
                          sortKey: _sortKey,
                          ascending: _ascending,
                          currency: currency,
                          onSort: _onSort,
                          onRefresh: () async => refreshActive(),
                          scrollController: ref.watch(
                            branchScrollControllerProvider(3),
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A receipt paired with its resolved product name(s), ready to render and
/// sort. Single-line receipts behave exactly like the pre-cart per-sale rows;
/// multi-line receipts (cart checkouts) lead with their first product name and
/// a "+N" badge for the rest, so a receipt reads as what it contains.
class _ReceiptRow {
  _ReceiptRow({required this.receipt, required this.names});

  final SaleReceipt receipt;
  final Map<String, String> names; // productId -> name, for every line

  bool get isSingle => receipt.lineCount == 1;

  /// The product name that leads the row: the sale's product for a single, or
  /// the receipt's first line for a checkout. Empty (deleted product) — the
  /// caller substitutes a localized "Sale" fallback.
  String get leadName => names[receipt.lines.first.productId] ?? '';

  /// Additional lines a receipt bundles beyond its lead (0 for a single sale);
  /// rendered as a muted "+N" badge next to [leadName].
  int get extraCount => receipt.lineCount - 1;

  /// Lower-cased sort key for the Item column: singles and receipts alike sort
  /// by their lead product name, so an A→Z sort reads as one intuitive list
  /// instead of clustering every receipt at the end.
  String get sortName {
    final name = (names[receipt.lines.first.productId] ?? '').toLowerCase();
    return name.isEmpty ? '~' : name;
  }

  /// Sort/display value for the Qty column: the actual quantity for a single
  /// sale, or the line count for a grouped checkout (mixed units can't sum
  /// meaningfully, so item count is the closest comparable proxy).
  double get qtyValue =>
      isSingle ? receipt.lines.single.quantity : receipt.lineCount.toDouble();

  String get qtyLabel {
    // A receipt bundles mixed units (kg + pcs …) that can't sum meaningfully,
    // so its Qty cell shows a dash; only a single sale shows a real quantity.
    if (!isSingle) return '—';
    return Qty.format(receipt.lines.single.quantity);
  }

  /// True if any line's product name contains [query] (or [query] is empty).
  bool matches(String query) {
    if (query.isEmpty) return true;
    for (final t in receipt.lines) {
      if ((names[t.productId] ?? '').toLowerCase().contains(query)) return true;
    }
    return false;
  }
}

/// Today / Week two-option segment. When [dayActive] is true a specific
/// calendar day is selected, so neither option is highlighted.
class _ScopeSelector extends StatelessWidget {
  const _ScopeSelector({
    required this.scope,
    required this.dayActive,
    required this.onChanged,
  });

  final _Scope scope;
  final bool dayActive;
  final ValueChanged<_Scope> onChanged;

  @override
  Widget build(BuildContext context) {
    return TwoOptionSegment<_Scope>(
      values: _Scope.values,
      selected: dayActive ? null : scope,
      height: 56,
      labelOf: (s) => switch (s) {
        _Scope.today => context.l10n.common_period_today,
        _Scope.week => context.l10n.common_period_week,
      },
      onChanged: onChanged,
    );
  }
}

/// The bordered card that holds a fixed header row over a scrolling list of
/// receipts. The header stays put while rows scroll under it.
class _SalesTable extends StatelessWidget {
  const _SalesTable({
    required this.rows,
    required this.sortKey,
    required this.ascending,
    required this.currency,
    required this.onSort,
    required this.onRefresh,
    required this.scrollController,
  });

  final List<_ReceiptRow> rows;
  final _SortKey sortKey;
  final bool ascending;
  final String currency;
  final void Function(_SortKey) onSort;
  final Future<void> Function() onRefresh;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = theme.extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      // One large card holding the table (design §8, Sales history).
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: colors.card(context),
        child: Column(
          children: [
            _HeaderRow(sortKey: sortKey, ascending: ascending, onSort: onSort),
            Divider(height: 1, color: scheme.outlineVariant),
            Expanded(
              child: rows.isEmpty
                  ? const _NoMatch()
                  : RefreshIndicator(
                      onRefresh: onRefresh,
                      child: ListView.separated(
                        controller: scrollController,
                        // Bottom padding clears the floating bottom nav.
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: rows.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: scheme.outlineVariant),
                        itemBuilder: (context, i) => _ReceiptTile(
                          key: ValueKey(rows[i].receipt.id),
                          row: rows[i],
                          currency: currency,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// Shared column widths so the header and every data row line up exactly.
// Trimmed from the original 58/40/88 to give the Item column more room so
// product names stop truncating to "Lifebuo…".
const double _timeW = 54;
const double _qtyW = 34;
const double _amtW = 78;

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.sortKey,
    required this.ascending,
    required this.onSort,
  });

  final _SortKey sortKey;
  final bool ascending;
  final void Function(_SortKey) onSort;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          _HeaderCell(
            label: l10n.history_colTime,
            width: _timeW,
            align: TextAlign.left,
            active: sortKey == _SortKey.time,
            ascending: ascending,
            onTap: () => onSort(_SortKey.time),
          ),
          _HeaderCell(
            label: l10n.history_colItem,
            active: sortKey == _SortKey.item,
            ascending: ascending,
            onTap: () => onSort(_SortKey.item),
          ),
          _HeaderCell(
            label: l10n.history_colQty,
            width: _qtyW,
            align: TextAlign.center,
            active: sortKey == _SortKey.qty,
            ascending: ascending,
            onTap: () => onSort(_SortKey.qty),
          ),
          _HeaderCell(
            label: l10n.history_colAmount,
            width: _amtW,
            align: TextAlign.right,
            accent: true,
            active: sortKey == _SortKey.amount,
            ascending: ascending,
            onTap: () => onSort(_SortKey.amount),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell({
    required this.label,
    required this.active,
    required this.ascending,
    required this.onTap,
    this.width,
    this.align = TextAlign.left,
    this.accent = false,
  });

  final String label;
  final bool active;
  final bool ascending;
  final VoidCallback onTap;
  final double? width;
  final TextAlign align;

  /// The Amount column is tinted brand-blue to signal it's the primary
  /// find-by-value affordance, even when it isn't the active sort.
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = accent || active
        ? theme.extension<AppColors>()!.link
        : scheme.onSurfaceVariant;
    final isRight = align == TextAlign.right;
    final isCenter = align == TextAlign.center;

    final cell = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 2),
        child: Row(
          mainAxisAlignment: isRight
              ? MainAxisAlignment.end
              : isCenter
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(
                label,
                textAlign: align,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontSize: 15,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (active)
              Icon(
                ascending ? Icons.arrow_upward : Icons.arrow_downward,
                size: 16,
                color: color,
              ),
          ],
        ),
      ),
    );

    return width == null
        ? Expanded(child: cell)
        : SizedBox(width: width, child: cell);
  }
}

/// One receipt: a summary row (Time · Item(s) · Qty · Amount), expandable into
/// its individual lines when it came from a multi-item cart checkout.
class _ReceiptTile extends StatefulWidget {
  const _ReceiptTile({super.key, required this.row, required this.currency});

  final _ReceiptRow row;
  final String currency;

  @override
  State<_ReceiptTile> createState() => _ReceiptTileState();
}

class _ReceiptTileState extends State<_ReceiptTile> {
  bool _expanded = false;

  String _time(DateTime? d) {
    final t = (d ?? DateTime.now()).toLocal();
    // DateFormat localizes the digits via Intl.defaultLocale, so the time
    // renders in Bengali digits (৯:০৫) when the app is in Bengali. AM/PM stays
    // in Latin — universally read on Bangladeshi shop signage and tills.
    final hm = DateFormat('h:mm').format(t);
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$hm$ampm';
  }

  String _lineQty(double v) => Qty.format(v);

  void _openDetail(Transaction line) =>
      context.push('${AppRoutes.saleDetail}/${line.id}', extra: line);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final row = widget.row;
    final canExpand = !row.isSingle;

    const tnum = [FontFeature.tabularFigures()];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: canExpand
              ? () => setState(() => _expanded = !_expanded)
              : () => _openDetail(widget.row.receipt.lines.single),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
            child: Row(
              children: [
                SizedBox(
                  width: _timeW,
                  // Scales down rather than clipping: the column is 54 dp.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _time(row.receipt.createdAt),
                      maxLines: 1,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontFeatures: tnum,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Row(
                      children: [
                        Flexible(
                          child: RichText(
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            text: TextSpan(
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                              children: [
                                TextSpan(
                                  text: row.leadName.isEmpty
                                      ? l10n.history_saleFallback
                                      : row.leadName,
                                ),
                                if (row.extraCount > 0)
                                  TextSpan(
                                    text: '  +${row.extraCount}',
                                    style: TextStyle(
                                      color: scheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        if (canExpand) ...[
                          const SizedBox(width: 4),
                          Icon(
                            _expanded ? Icons.expand_less : Icons.expand_more,
                            size: 16,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: _qtyW,
                  child: Text(
                    row.qtyLabel,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontFeatures: tnum,
                    ),
                  ),
                ),
                SizedBox(
                  width: _amtW,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      Money.compact(
                        row.receipt.totalRevenue,
                        currencyCode: widget.currency,
                      ),
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        fontFeatures: tnum,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            width: double.infinity,
            color: scheme.surfaceContainer.withValues(alpha: 0.45),
            padding: const EdgeInsets.only(top: 6, bottom: 10),
            child: Column(
              children: [
                for (final line in row.receipt.lines)
                  InkWell(
                    onTap: () => _openDetail(line),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
                      child: Row(
                        children: [
                          SizedBox(
                            width: _timeW,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 9),
                                child: Container(
                                  width: 4,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: scheme.onSurfaceVariant,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              (row.names[line.productId]?.isNotEmpty ?? false)
                                  ? row.names[line.productId]!
                                  : l10n.history_saleFallback,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: _qtyW,
                            child: Text(
                              _lineQty(line.quantity),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontFeatures: tnum,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: _amtW,
                            child: Text(
                              Money.compact(
                                line.revenue,
                                currencyCode: widget.currency,
                              ),
                              textAlign: TextAlign.right,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                                fontFeatures: tnum,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // The receipt-level discount, shown once under the lines. The
                // per-line amounts above are already net, so without this the
                // figure the shopkeeper typed is nowhere in History and the
                // lines look like they simply cost less than the products do.
                if (row.receipt.discountTotal > 0)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                    child: Row(
                      children: [
                        SizedBox(width: _timeW),
                        Expanded(
                          child: Text(
                            l10n.saleDetail_discount,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                        SizedBox(width: _qtyW),
                        SizedBox(
                          width: _amtW,
                          child: Text(
                            '−${Money.compact(row.receipt.discountTotal, currencyCode: widget.currency)}',
                            textAlign: TextAlign.right,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontStyle: FontStyle.italic,
                              fontFeatures: tnum,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Shown inside the table when a search/scope yields no rows (but sales exist).
class _NoMatch extends StatelessWidget {
  const _NoMatch();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 10),
            Text(
              context.l10n.history_noMatch,
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
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Skeleton(width: 180, height: 28),
          const SizedBox(height: 16),
          const Skeleton(width: double.infinity, height: 52, radius: 12),
          const SizedBox(height: 12),
          const Skeleton(width: double.infinity, height: 44, radius: 12),
          const SizedBox(height: 16),
          for (var i = 0; i < 8; i++) ...[
            const Skeleton(width: double.infinity, height: 40, radius: 8),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message, this.showHint = true});

  final String message;

  /// The "Add to cart from Items…" hint only makes sense when the shop has no
  /// sales at all — it's hidden when a specific (empty) day is selected.
  final bool showHint;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 56,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (showHint) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                context.l10n.history_emptyHint,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline,
            size: 56,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(message, textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: onRetry,
            child: Text(context.l10n.common_retry),
          ),
        ],
      ),
    );
  }
}

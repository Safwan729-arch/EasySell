import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/rounded_icon_tile.dart';
import '../../auth/data/auth_repository.dart';
import '../data/trend_repository.dart';
import '../domain/trend.dart';

/// Read-only trend dashboards (// MEMBER B writes `trend_data`).
final trendsProvider = FutureProvider.autoDispose<List<Trend>>((ref) async {
  final shop = ref.watch(myShopProvider).value;
  if (shop == null) return const [];
  final result = await ref.watch(trendRepositoryProvider).fetchTrends(shop.id);
  return result.when(success: (v) => v, failure: (f) => throw f);
});

class TrendScreen extends ConsumerWidget {
  const TrendScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(trendsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.trends_title)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(trendsProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Centered(
            icon: Icons.error_outline,
            message: l10n.trends_couldNotLoad,
          ),
          data: (trends) {
            if (trends.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  _Centered(
                    icon: Icons.insights_outlined,
                    message: l10n.trends_empty,
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: trends.length,
              itemBuilder: (_, i) => _TrendCard(trend: trends[i]),
            );
          },
        ),
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.trend});

  final Trend trend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final max = trend.maxValue;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                RoundedIconTile(icon: Icons.trending_up),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trend.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (trend.metric != null)
                        Text(
                          trend.metric!,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (trend.points.isEmpty)
              Text(
                context.l10n.trends_noData,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              )
            else
              for (final p in trend.points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              p.label,
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            // NumberFormat, not toStringAsFixed, so the digits
                            // follow the app language like every other figure.
                            NumberFormat(
                              p.value.truncateToDouble() == p.value
                                  ? '#,##0'
                                  : '#,##0.00',
                            ).format(p.value),
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: max <= 0 ? 0 : (p.value / max).clamp(0, 1),
                          minHeight: 8,
                          backgroundColor: scheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

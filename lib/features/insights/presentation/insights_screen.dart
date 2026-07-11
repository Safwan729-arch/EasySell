import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/rounded_icon_tile.dart';
import '../../auth/data/auth_repository.dart';
import '../data/insights_repository.dart';
import '../domain/insight.dart';

/// Read-only list of AI insights (// MEMBER B writes them). Never editable here.
final insightsProvider = FutureProvider.autoDispose<List<Insight>>((ref) async {
  final shop = ref.watch(myShopProvider).value;
  if (shop == null) return const [];
  final result = await ref
      .watch(insightsRepositoryProvider)
      .fetchInsights(shop.id);
  return result.when(success: (v) => v, failure: (f) => throw f);
});

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final async = ref.watch(insightsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.insights_title)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(insightsProvider),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _CenteredMessage(
            icon: Icons.error_outline,
            message: l10n.insights_couldNotLoad,
          ),
          data: (insights) {
            if (insights.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  _CenteredMessage(
                    icon: Icons.lightbulb_outline,
                    message: l10n.insights_empty,
                  ),
                ],
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: insights.length,
              itemBuilder: (_, i) => _InsightCard(insight: insights[i]),
            );
          },
        ),
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight});

  final Insight insight;

  ({Color color, IconData icon}) _style(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return switch (insight.severity) {
      'critical' => (color: scheme.error, icon: Icons.priority_high),
      'warning' => (color: scheme.tertiary, icon: Icons.warning_amber_rounded),
      _ => (color: scheme.primary, icon: Icons.lightbulb_outline),
    };
  }

  @override
  Widget build(BuildContext context) {
    final s = _style(context);
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RoundedIconTile(icon: s.icon, color: s.color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    insight.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (insight.body.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      insight.body,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

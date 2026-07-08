import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../../shared/providers/theme_mode_provider.dart';

/// Profile + shop info (read-only) and sign out.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final shop = ref.watch(myShopProvider).value;
    final isGuest = user?.isAnonymous ?? false;
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Profile'),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(
              isGuest ? 'Guest session' : (user?.email ?? 'Signed in'),
            ),
            subtitle: Text(
              isGuest ? 'Anonymous — data is tied to this device' : 'Signed in',
            ),
          ),
          const Divider(),
          const _SectionHeader('Shop'),
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: Text(shop?.name ?? '—'),
            subtitle: const Text('Shop name'),
          ),
          if (shop?.address != null && shop!.address!.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(shop.address!),
              subtitle: const Text('Address'),
            ),
          if (shop?.phone != null && shop!.phone!.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text(shop.phone!),
              subtitle: const Text('Phone'),
            ),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(shop?.currency ?? 'USD'),
            subtitle: const Text('Currency'),
          ),
          const Divider(),
          const _SectionHeader('Assistant'),
          ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: const Text('AI Insights'),
            subtitle: const Text('Suggestions from the assistant'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.insights),
          ),
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text('Trends'),
            subtitle: const Text('Sales trend dashboards'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.trends),
          ),
          const Divider(),
          const _SectionHeader('Appearance'),
          const _ThemeModeSelector(),
          const Divider(),
          const _SectionHeader('Inventory'),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Manage categories'),
            subtitle: const Text('Rename, add, or remove categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.categories),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: const Text('Archived products'),
            subtitle: const Text('View and restore removed products'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.archivedProducts),
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: isLoading
                  ? null
                  : () => ref.read(authControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Light / Dark theme picker. The choice is persisted via [themeModeProvider].
class _ThemeModeSelector extends ConsumerWidget {
  const _ThemeModeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    // The selector only offers Light/Dark, so a legacy `system` preference has
    // no matching segment — render it as Light (which is how it resolves below).
    final selected = mode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.light,
            label: Text('Light'),
            icon: Icon(Icons.light_mode_outlined),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            label: Text('Dark'),
            icon: Icon(Icons.dark_mode_outlined),
          ),
        ],
        selected: {selected},
        showSelectedIcon: false,
        onSelectionChanged: (selection) =>
            ref.read(themeModeProvider.notifier).setMode(selection.first),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

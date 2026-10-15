import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../expiry/presentation/expiry_settings_tiles.dart';
import '../../restock/presentation/restock_settings_tile.dart';
import '../../../shared/providers/locale_provider.dart';
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

    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings_title)),
      body: ListView(
        children: [
          _SectionHeader(l10n.settings_sectionProfile),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(
              isGuest
                  ? l10n.settings_guestSession
                  : (user?.email ?? l10n.settings_signedIn),
            ),
            subtitle: Text(
              isGuest ? l10n.settings_anonymousData : l10n.settings_signedIn,
            ),
          ),
          const Divider(),
          _SectionHeader(l10n.settings_sectionShop),
          ListTile(
            leading: const Icon(Icons.storefront_outlined),
            title: Text(shop?.name ?? '—'),
            subtitle: Text(l10n.settings_shopName),
          ),
          if (shop?.address != null && shop!.address!.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(shop.address!),
              subtitle: Text(l10n.settings_address),
            ),
          if (shop?.phone != null && shop!.phone!.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.phone_outlined),
              title: Text(shop.phone!),
              subtitle: Text(l10n.settings_phone),
            ),
          ListTile(
            leading: const Icon(Icons.payments_outlined),
            title: Text(shop?.currency ?? 'USD'),
            subtitle: Text(l10n.settings_currency),
          ),
          const Divider(),
          _SectionHeader(l10n.settings_sectionLanguage),
          const _LanguageSelector(),
          const Divider(),
          _SectionHeader(l10n.settings_sectionAssistant),
          ListTile(
            leading: const Icon(Icons.lightbulb_outline),
            title: Text(l10n.settings_aiInsights),
            subtitle: Text(l10n.settings_aiInsightsSub),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.insights),
          ),
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: Text(l10n.settings_trends),
            subtitle: Text(l10n.settings_trendsSub),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.trends),
          ),
          const Divider(),
          _SectionHeader(l10n.settings_sectionAppearance),
          const _ThemeModeSelector(),
          const Divider(),
          _SectionHeader(l10n.settings_sectionInventory),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: Text(l10n.settings_manageCategories),
            subtitle: Text(l10n.settings_manageCategoriesSub),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.categories),
          ),
          ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text(l10n.settings_archivedProducts),
            subtitle: Text(l10n.settings_archivedProductsSub),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AppRoutes.archivedProducts),
          ),
          const RestockDaysTile(),
          const Divider(),
          _SectionHeader(l10n.settings_sectionExpiry),
          const ExpiryWarnDaysTile(),
          const ExpiryReminderTile(),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: OutlinedButton.icon(
              onPressed: isLoading
                  ? null
                  : () => ref.read(authControllerProvider.notifier).signOut(),
              icon: const Icon(Icons.logout),
              label: Text(l10n.common_signOut),
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
        segments: [
          ButtonSegment(
            value: ThemeMode.light,
            label: Text(context.l10n.settings_themeLight),
            icon: const Icon(Icons.light_mode_outlined),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            label: Text(context.l10n.settings_themeDark),
            icon: const Icon(Icons.dark_mode_outlined),
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

/// English / বাংলা picker. The choice is persisted via [localeProvider] and
/// applied app-wide by MaterialApp.router. The language names are endonyms
/// (shown the same in both modes), so they stay literal rather than ARB keys.
class _LanguageSelector extends ConsumerWidget {
  const _LanguageSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final selected = locale.languageCode == 'bn'
        ? const Locale('bn')
        : const Locale('en');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SegmentedButton<Locale>(
        segments: const [
          ButtonSegment(
            value: Locale('en'),
            label: Text('English'),
            icon: Icon(Icons.language),
          ),
          ButtonSegment(
            value: Locale('bn'),
            label: Text('বাংলা'),
            icon: Icon(Icons.translate),
          ),
        ],
        selected: {selected},
        showSelectedIcon: false,
        onSelectionChanged: (selection) =>
            ref.read(localeProvider.notifier).setLocale(selection.first),
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

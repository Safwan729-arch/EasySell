import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/theme.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/section_bits.dart';
import '../../../core/widgets/two_option_segment.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../expiry/presentation/expiry_settings_tiles.dart';
import '../../restock/presentation/restock_settings_tile.dart';
import '../../../shared/providers/locale_provider.dart';
import '../../../shared/providers/supabase_provider.dart';
import '../../../shared/providers/theme_mode_provider.dart';

/// Profile + shop info (read-only), preferences, and sign out. Each section is
/// its own card with a blue spaced-caps label (design §8, Settings).
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
      body: ListTileTheme(
        // Rows inside the section cards: 17 / 500 titles, muted subtitles.
        data: ListTileThemeData(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          minVerticalPadding: 12,
          horizontalTitleGap: 16,
          titleTextStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontSize: 17,
            fontWeight: FontWeight.w500,
          ),
          subtitleTextStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            _Section(
              title: l10n.settings_sectionProfile,
              children: [
                ListTile(
                  leading: const SettingsIconTile(Icons.person_outline),
                  title: Text(
                    isGuest
                        ? l10n.settings_guestSession
                        : (user?.email ?? l10n.settings_signedIn),
                  ),
                  subtitle: Text(
                    isGuest
                        ? l10n.settings_anonymousData
                        : l10n.settings_signedIn,
                  ),
                ),
              ],
            ),
            _Section(
              title: l10n.settings_sectionShop,
              children: [
                ListTile(
                  leading: const SettingsIconTile(Icons.storefront_outlined),
                  title: Text(shop?.name ?? '—'),
                  subtitle: Text(l10n.settings_shopName),
                ),
                if (shop?.address != null && shop!.address!.isNotEmpty)
                  ListTile(
                    leading: const SettingsIconTile(Icons.location_on_outlined),
                    title: Text(shop.address!),
                    subtitle: Text(l10n.settings_address),
                  ),
                if (shop?.phone != null && shop!.phone!.isNotEmpty)
                  ListTile(
                    leading: const SettingsIconTile(Icons.phone_outlined),
                    title: Text(shop.phone!),
                    subtitle: Text(l10n.settings_phone),
                  ),
                ListTile(
                  leading: const SettingsIconTile(Icons.payments_outlined),
                  title: Text(shop?.currency ?? 'USD'),
                  subtitle: Text(l10n.settings_currency),
                ),
              ],
            ),
            _Section(
              title: l10n.settings_sectionLanguage,
              children: const [_LanguageSelector()],
            ),
            _Section(
              title: l10n.settings_sectionAssistant,
              children: [
                ListTile(
                  leading: const SettingsIconTile(Icons.lightbulb_outline),
                  title: Text(l10n.settings_aiInsights),
                  subtitle: Text(l10n.settings_aiInsightsSub),
                  trailing: const _Chevron(),
                  onTap: () => context.push(AppRoutes.insights),
                ),
                ListTile(
                  leading: const SettingsIconTile(Icons.insights_outlined),
                  title: Text(l10n.settings_trends),
                  subtitle: Text(l10n.settings_trendsSub),
                  trailing: const _Chevron(),
                  onTap: () => context.push(AppRoutes.trends),
                ),
              ],
            ),
            _Section(
              title: l10n.settings_sectionAppearance,
              children: const [_ThemeModeSelector()],
            ),
            _Section(
              title: l10n.settings_sectionInventory,
              children: [
                ListTile(
                  leading: const SettingsIconTile(Icons.category_outlined),
                  title: Text(l10n.settings_manageCategories),
                  subtitle: Text(l10n.settings_manageCategoriesSub),
                  trailing: const _Chevron(),
                  onTap: () => context.push(AppRoutes.categories),
                ),
                ListTile(
                  leading: const SettingsIconTile(Icons.inventory_2_outlined),
                  title: Text(l10n.settings_archivedProducts),
                  subtitle: Text(l10n.settings_archivedProductsSub),
                  trailing: const _Chevron(),
                  onTap: () => context.push(AppRoutes.archivedProducts),
                ),
                const RestockDaysTile(),
              ],
            ),
            _Section(
              title: l10n.settings_sectionExpiry,
              children: const [ExpiryWarnDaysTile(), ExpiryReminderTile()],
            ),
            // Sign out: a full-width outlined card button.
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isLoading
                    ? null
                    : () => ref.read(authControllerProvider.notifier).signOut(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(22),
                  ),
                ),
                icon: const Icon(Icons.logout),
                label: Text(l10n.common_signOut),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One settings group: a card with a blue spaced-caps label over its rows,
/// rows split by hairlines.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Eyebrow(title, color: colors.sectionLabel),
            ),
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class _Chevron extends StatelessWidget {
  const _Chevron();

  @override
  Widget build(BuildContext context) => Icon(
    Icons.chevron_right_rounded,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
  );
}

/// Light / Dark theme picker. The choice is persisted via [themeModeProvider].
class _ThemeModeSelector extends ConsumerWidget {
  const _ThemeModeSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    // The selector only offers Light/Dark, so a legacy `system` preference has
    // no matching option — render it as Light (which is how it resolves below).
    final selected = mode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
      child: TwoOptionSegment<ThemeMode>(
        values: const [ThemeMode.light, ThemeMode.dark],
        selected: selected,
        labelOf: (m) => m == ThemeMode.dark
            ? context.l10n.settings_themeDark
            : context.l10n.settings_themeLight,
        iconOf: (m) => m == ThemeMode.dark
            ? Icons.dark_mode_outlined
            : Icons.light_mode_outlined,
        onChanged: (m) => ref.read(themeModeProvider.notifier).setMode(m),
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
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 8),
      child: TwoOptionSegment<Locale>(
        values: const [Locale('en'), Locale('bn')],
        selected: selected,
        labelOf: (l) => l.languageCode == 'bn' ? 'বাংলা' : 'English',
        iconOf: (l) =>
            l.languageCode == 'bn' ? Icons.translate : Icons.language,
        onChanged: (l) => ref.read(localeProvider.notifier).setLocale(l),
      ),
    );
  }
}

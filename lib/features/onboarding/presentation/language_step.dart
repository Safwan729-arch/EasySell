import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n_ext.dart';
import '../../../shared/providers/locale_provider.dart';

/// Step 1 of onboarding: a compulsory language choice. Tapping a card applies
/// the locale live (the whole app — this screen included — switches) and enables
/// [onContinue]; until a card is tapped, Continue stays disabled so the choice
/// cannot be skipped. Language names are endonyms, shown the same in both modes.
class LanguageStep extends ConsumerStatefulWidget {
  const LanguageStep({super.key, required this.onContinue});

  final VoidCallback onContinue;

  @override
  ConsumerState<LanguageStep> createState() => _LanguageStepState();
}

class _LanguageStepState extends ConsumerState<LanguageStep> {
  Locale? _picked;

  void _pick(Locale locale) {
    ref.read(localeProvider.notifier).setLocale(locale);
    setState(() => _picked = locale);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    // Scroll-safe layout: on a tall viewport the Spacer pins Continue to the
    // bottom; on a short one (e.g. landscape) the content scrolls instead of
    // overflowing.
    return LayoutBuilder(
      builder: (context, constraints) {
        const padding = EdgeInsets.fromLTRB(24, 16, 24, 24);
        return SingleChildScrollView(
          padding: padding,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight - padding.vertical,
            ),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l10n.onboarding_languageTitle,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.onboarding_languageSubtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _LanguageCard(
                    label: 'English',
                    selected: _picked == const Locale('en'),
                    onTap: () => _pick(const Locale('en')),
                  ),
                  const SizedBox(height: 12),
                  _LanguageCard(
                    label: 'বাংলা',
                    selected: _picked == const Locale('bn'),
                    onTap: () => _pick(const Locale('bn')),
                  ),
                  const SizedBox(height: 24),
                  const Spacer(),
                  FilledButton(
                    onPressed: _picked == null ? null : widget.onContinue,
                    child: Text(l10n.common_continue),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.10)
              : scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ],
        ),
      ),
    );
  }
}

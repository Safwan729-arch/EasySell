import 'package:flutter/widgets.dart';

import 'package:ai_shopkeeper/l10n/app_localizations.dart';

/// Ergonomic access to generated strings: `context.l10n.settings_title`.
/// Non-null because `nullable-getter: false` is set in l10n.yaml.
extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

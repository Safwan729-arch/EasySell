import 'package:ai_shopkeeper/l10n/app_localizations.dart';

import '../../features/customers/domain/ledger_entry.dart';

/// Localized label for a ledger row's type, used by the customer-detail history.
String ledgerEntryTypeLabel(AppLocalizations l10n, LedgerEntryType t) =>
    switch (t) {
      LedgerEntryType.creditSale => l10n.customers_ledgerCreditSale,
      LedgerEntryType.payment => l10n.customers_ledgerPayment,
    };

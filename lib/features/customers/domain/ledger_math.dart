import 'ledger_entry.dart';

/// A customer's balance from their ledger: credit sales add, payments subtract.
/// Display/verification helper — Postgres remains the source of truth for what
/// is persisted (see `get_customer_balances`).
double balanceOf(List<LedgerEntry> entries) {
  var total = 0.0;
  for (final e in entries) {
    total += switch (e.entryType) {
      LedgerEntryType.creditSale => e.amount,
      LedgerEntryType.payment => -e.amount,
    };
  }
  return total;
}

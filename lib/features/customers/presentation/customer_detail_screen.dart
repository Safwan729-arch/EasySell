import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/config/haptics.dart';
import '../../../core/config/theme.dart';
import '../../../core/error/failure.dart';
import '../../../core/l10n/customer_labels.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../../core/widgets/brand_fill.dart';
import '../../../shared/extensions/format.dart';
import '../../auth/data/auth_repository.dart';
import '../domain/customer.dart';
import '../domain/customer_balance.dart';
import '../domain/ledger_entry.dart';
import '../domain/ledger_math.dart';
import 'customer_detail_controller.dart';
import 'customer_form_sheet.dart';
import 'customers_controller.dart';
import 'record_payment_sheet.dart';

/// A single customer's khata: running balance plus the full ledger
/// (credit sales and payments), newest first. Looks the customer's live
/// balance up from [customersControllerProvider] by id; if that list hasn't
/// (yet) surfaced this customer, the balance is instead derived from the
/// ledger itself so the screen still renders something sensible.
class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final detailAsync = ref.watch(
      customerDetailControllerProvider(customerId),
    );
    final customers =
        ref.watch(customersControllerProvider).value ?? const <CustomerBalance>[];
    final currency = ref.watch(myShopProvider).value?.currency ?? 'USD';

    CustomerBalance? balanceRow;
    for (final c in customers) {
      if (c.id == customerId) {
        balanceRow = c;
        break;
      }
    }

    ref.listen<AsyncValue<List<LedgerEntry>>>(
      customerDetailControllerProvider(customerId),
      (_, next) {
        if (next is AsyncError) {
          final message = switch (next.error) {
            Failure(:final message) => message,
            _ => l10n.common_somethingWrong,
          };
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(message)));
        }
      },
    );

    final entries = detailAsync.value;
    final balance = balanceRow?.balance ?? (entries != null ? balanceOf(entries) : 0.0);
    final paymentCustomer =
        balanceRow ??
        CustomerBalance(id: customerId, name: '', phone: '', balance: balance);

    return Scaffold(
      appBar: AppBar(
        title: Text(balanceRow?.name ?? ''),
        actions: [
          if (balanceRow != null)
            IconButton(
              tooltip: l10n.common_edit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => showCustomerFormSheet(
                context,
                existing: Customer(
                  id: balanceRow!.id,
                  shopId: '',
                  name: balanceRow.name,
                  phone: balanceRow.phone,
                  note: balanceRow.note,
                ),
              ),
            ),
          if (balanceRow != null)
            IconButton(
              tooltip: l10n.customers_delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () =>
                  _confirmDelete(context, ref, balanceRow!.id, balanceRow.name),
            ),
        ],
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text(e is Failure ? e.message : l10n.common_somethingWrong),
        ),
        data: (ledger) {
          final sorted = [...ledger]
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return Column(
            children: [
              _BalanceHeader(balance: balance, currency: currency),
              Expanded(
                child: sorted.isEmpty
                    ? Center(child: Text(l10n.customers_ledgerEmpty))
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 16),
                        itemCount: sorted.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) =>
                            _LedgerTile(entry: sorted[i], currency: currency),
                      ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: balance == 0
                ? null
                : () => showRecordPaymentSheet(context, customer: paymentCustomer),
            child: Text(l10n.customers_recordPayment),
          ),
        ),
      ),
    );
  }

  /// Confirms destructive delete (mirrors `cart_screen.dart`'s
  /// `_confirmClear` styling), then calls through to
  /// [CustomersController.deleteCustomer]. On success, pops back to the
  /// customers list; on failure (e.g. the customer still owes money), shows
  /// the RPC's message in a floating snackbar and leaves this screen open.
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    String id,
    String name,
  ) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(l10n.customers_deleteConfirmTitle(name)),
          content: Text(l10n.customers_deleteConfirmBody),
          // Natural-width actions: the theme forces FilledButton to a
          // full-width minimumSize, which makes a dialog's confirm button
          // dwarf the text "Cancel". Reset it so both size to their content.
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.common_cancel),
            ),
            FilledButton(
              style: destructiveButtonStyle(ctx),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.common_delete),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final failure = await ref
        .read(customersControllerProvider.notifier)
        .deleteCustomer(id);
    if (!context.mounted) return;

    if (failure == null) {
      AppHaptics.success();
      context.pop();
    } else {
      AppHaptics.warning();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(failure.message),
          ),
        );
    }
  }
}

class _BalanceHeader extends StatelessWidget {
  const _BalanceHeader({required this.balance, required this.currency});

  final double balance;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.customers_balance,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            Money.format(balance, currencyCode: currency),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: balance > 0 ? colors.negative : colors.positive,
            ),
          ),
        ],
      ),
    );
  }
}

class _LedgerTile extends StatelessWidget {
  const _LedgerTile({required this.entry, required this.currency});

  final LedgerEntry entry;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final isCredit = entry.entryType == LedgerEntryType.creditSale;
    final sign = isCredit ? '+' : '−';
    final color = isCredit ? colors.negative : colors.positive;
    return ListTile(
      title: Text(ledgerEntryTypeLabel(l10n, entry.entryType)),
      subtitle: Text(
        DateFormat('d MMM y, h:mm a').format(entry.createdAt),
      ),
      trailing: Text(
        '$sign${Money.format(entry.amount, currencyCode: currency)}',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

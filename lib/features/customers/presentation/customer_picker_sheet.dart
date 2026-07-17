import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../domain/customer.dart';
import '../domain/customer_balance.dart';
import 'customer_form_sheet.dart';
import 'customers_controller.dart';

/// Bottom sheet listing the shop's customers with a name/phone search and a
/// "+ Add new" affordance (opens Task 7's form sheet, then refreshes this
/// list so the newcomer is pickable). Tapping a row resolves the picker with
/// a [Customer] built from that row's [CustomerBalance]; dismissing resolves
/// with null. Used by the cart's Credit flow to attach a customer to a sale.
Future<Customer?> showCustomerPickerSheet(BuildContext context) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => const _CustomerPickerSheet(),
  );
}

class _CustomerPickerSheet extends ConsumerStatefulWidget {
  const _CustomerPickerSheet();

  @override
  ConsumerState<_CustomerPickerSheet> createState() =>
      _CustomerPickerSheetState();
}

class _CustomerPickerSheetState extends ConsumerState<_CustomerPickerSheet> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<CustomerBalance> _filter(List<CustomerBalance> customers) {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return customers;
    return customers
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.phone.toLowerCase().contains(q),
        )
        .toList();
  }

  Future<void> _addNew() async {
    await showCustomerFormSheet(context);
    if (!mounted) return;
    // Refresh so the newly-added customer shows up in the list below;
    // the user still explicitly taps them to choose (no auto-select).
    await ref.read(customersControllerProvider.notifier).refresh();
  }

  void _choose(CustomerBalance c) {
    Navigator.of(context).pop(
      Customer(id: c.id, shopId: '', name: c.name, phone: c.phone, note: c.note),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final customersAsync = ref.watch(customersControllerProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.cart_selectCustomer,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l10n.customers_searchHint,
              prefixIcon: const Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 4),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.add_circle_outline),
            title: Text(l10n.customers_add),
            onTap: _addNew,
          ),
          const Divider(height: 1),
          Flexible(
            child: customersAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    e is Failure ? e.message : l10n.common_somethingWrong,
                  ),
                ),
              ),
              data: (customers) {
                if (customers.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text(l10n.customers_empty)),
                  );
                }
                final filtered = _filter(customers);
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = filtered[i];
                    return ListTile(
                      title: Text(c.name),
                      subtitle: Text(c.phone),
                      onTap: () => _choose(c),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/haptics.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../domain/customer.dart';
import 'customers_controller.dart';

Future<void> showCustomerFormSheet(
  BuildContext context, {
  Customer? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CustomerFormSheet(existing: existing),
  );
}

class _CustomerFormSheet extends ConsumerStatefulWidget {
  const _CustomerFormSheet({this.existing});
  final Customer? existing;

  @override
  ConsumerState<_CustomerFormSheet> createState() => _CustomerFormSheetState();
}

class _CustomerFormSheetState extends ConsumerState<_CustomerFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final notifier = ref.read(customersControllerProvider.notifier);
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final ok = widget.existing == null
        ? await notifier.createCustomer(name: name, phone: phone, note: note)
        : await notifier.updateCustomer(
            id: widget.existing!.id, name: name, phone: phone, note: note);
    if (!mounted) return;
    setState(() => _submitting = false);
    if (ok) {
      AppHaptics.success();
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? l10n.customers_add : l10n.customers_edit,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: l10n.customers_fieldName),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? l10n.customers_nameRequired : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: l10n.customers_fieldPhone),
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? l10n.customers_phoneRequired : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: InputDecoration(labelText: l10n.customers_fieldNote),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(l10n.customers_save),
            ),
          ],
        ),
      ),
    );
  }
}

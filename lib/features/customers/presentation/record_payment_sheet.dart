import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/config/haptics.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../domain/customer_balance.dart';
import 'customer_detail_controller.dart';

Future<void> showRecordPaymentSheet(
  BuildContext context, {
  required CustomerBalance customer,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RecordPaymentSheet(customer: customer),
  );
}

class _RecordPaymentSheet extends ConsumerStatefulWidget {
  const _RecordPaymentSheet({required this.customer});
  final CustomerBalance customer;

  @override
  ConsumerState<_RecordPaymentSheet> createState() =>
      _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends ConsumerState<_RecordPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _submitting = false;
  String? _error;

  /// The id sent with the last attempt, and the amount and note it was for.
  /// A failed attempt may still have been saved (a lost reply), so retrying
  /// the SAME payment re-sends the same id and the server records it once.
  /// A changed amount or note is a different payment and gets a new id.
  String? _paymentId;
  String? _paymentKey;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amount = double.parse(_amount.text.trim());
    final note = _note.text.trim().isEmpty ? null : _note.text.trim();
    final key = '$amount|${note ?? ''}';
    if (key != _paymentKey) {
      _paymentId = const Uuid().v4();
      _paymentKey = key;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    final failure = await ref
        .read(customerDetailControllerProvider(widget.customer.id).notifier)
        .recordPayment(amount: amount, paymentId: _paymentId!, note: note);
    if (!mounted) return;
    setState(() {
      _submitting = false;
      _error = failure?.message;
    });
    if (failure == null) {
      AppHaptics.success();
      final l10n = context.l10n;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(l10n.customers_paymentRecorded),
          ),
        );
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
              l10n.customers_recordPayment,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: l10n.customers_paymentAmount,
              ),
              validator: (v) {
                final parsed = double.tryParse((v ?? '').trim());
                if (parsed == null || parsed <= 0) {
                  return l10n.customers_paymentAmountRequired;
                }
                if (parsed > widget.customer.balance) {
                  return l10n.customers_paymentTooLarge;
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _note,
              decoration: InputDecoration(
                labelText: l10n.customers_paymentNote,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: Text(l10n.customers_recordPayment),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/failure.dart';
import '../../../core/l10n/l10n_ext.dart';
import '../../inventory/domain/product.dart';
import '../domain/expiry_dates.dart';
import '../domain/product_batch.dart';
import 'batch_actions_controller.dart';
import 'expiry_date_field.dart';
import 'expiry_providers.dart';
import 'today_provider.dart';

/// Add an expiry date to stock already on the shelf ([batch] null), or edit a
/// delivery. Returns true when saved.
Future<bool?> showBatchFormSheet(
  BuildContext context, {
  required Product product,
  ProductBatch? batch,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _BatchFormSheet(product: product, batch: batch),
  );
}

class _BatchFormSheet extends ConsumerStatefulWidget {
  const _BatchFormSheet({required this.product, this.batch});

  final Product product;
  final ProductBatch? batch;

  @override
  ConsumerState<_BatchFormSheet> createState() => _BatchFormSheetState();
}

class _BatchFormSheetState extends ConsumerState<_BatchFormSheet> {
  late final TextEditingController _amount;
  DateTime? _expiry;
  DateTime? _received;
  String? _error;

  bool get _isEdit => widget.batch != null;

  @override
  void initState() {
    super.initState();
    final b = widget.batch;
    _expiry = b?.expiryDate;
    _received = b?.receivedOn;
    _amount = TextEditingController(text: _plain(b?.quantity ?? _uncovered()));
  }

  /// Stock not yet covered by an open delivery -- the default amount when
  /// adding a date to stock already on the shelf (spec §3.3).
  double _uncovered() {
    final e = ref.read(productExpiryProvider)[widget.product.id];
    final covered = e == null
        ? 0.0
        : e.batches.fold<double>(0, (s, b) => s + b.left);
    final rest = widget.product.quantity - covered;
    return rest > 0 ? rest : widget.product.quantity;
  }

  /// Plain ASCII digits for the text field (see add_to_cart_sheet: `Qty.format`
  /// localises digits, which `double.tryParse` cannot read back).
  String _plain(double v) => v == v.roundToDouble()
      ? v.toStringAsFixed(0)
      : v
            .toStringAsFixed(3)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _pickReceived() async {
    final today = ref.read(todayProvider);
    final picked = await showDatePicker(
      context: context,
      initialDate: _received ?? today,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
    );
    if (picked != null) setState(() => _received = dateOnly(picked));
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final qty = double.tryParse(_amount.text.trim()) ?? 0;
    final wholeOnly = !widget.product.unitType.allowsDecimal;
    if (qty <= 0 || (wholeOnly && qty != qty.roundToDouble())) {
      setState(() => _error = l10n.expiry_amountInvalid);
      return;
    }
    final expiry = _expiry;
    if (expiry == null) {
      setState(() => _error = l10n.expiry_dateRequired);
      return;
    }
    setState(() => _error = null);
    final actions = ref.read(batchActionsControllerProvider.notifier);
    final ok = _isEdit
        ? await actions.editBatch(
            widget.batch!,
            quantity: qty,
            expiryDate: expiry,
          )
        : await actions.addBatch(
            product: widget.product,
            quantity: qty,
            expiryDate: expiry,
            receivedOn: _received ?? ref.read(todayProvider),
          );
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isLoading = ref.watch(batchActionsControllerProvider).isLoading;

    // Default "date added" for existing stock: the latest restock, else the
    // day the product was created, else today (spec §4.3 -- today would shrink
    // a long shelf life and the warning with it).
    if (!_isEdit && _received == null) {
      final latest = ref.watch(latestRestockDateProvider(widget.product.id));
      final fallback = widget.product.createdAt == null
          ? ref.read(todayProvider)
          : dateOnly(widget.product.createdAt!.toLocal());
      if (!latest.isLoading) _received = latest.value ?? fallback;
    }

    ref.listen<AsyncValue<void>>(batchActionsControllerProvider, (_, next) {
      if (next is AsyncError) {
        setState(() {
          _error = switch (next.error) {
            Failure(:final message) => message,
            _ => l10n.common_somethingWrong,
          };
        });
      }
    });

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _isEdit ? l10n.expiry_formEditTitle : l10n.expiry_formAddTitle,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(widget.product.name, style: theme.textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _amount,
            enabled: !isLoading,
            keyboardType: TextInputType.numberWithOptions(
              decimal: widget.product.unitType.allowsDecimal,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.allow(
                widget.product.unitType.allowsDecimal
                    ? RegExp(r'[0-9.]')
                    : RegExp(r'[0-9]'),
              ),
            ],
            decoration: InputDecoration(
              labelText: l10n.expiry_formAmount,
              suffixText: widget.product.unitLabel,
            ),
          ),
          const SizedBox(height: 16),
          ExpiryDateField(
            value: _expiry,
            enabled: !isLoading,
            onChanged: (d) => setState(() => _expiry = d),
          ),
          if (!_isEdit)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.expiry_formReceived),
              trailing: Text(
                _received == null ? '' : formatExpiryDate(context, _received!),
                style: theme.textTheme.bodyLarge,
              ),
              onTap: isLoading ? null : _pickReceived,
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isLoading
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: Text(l10n.common_cancel),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: isLoading ? null : _save,
                  child: Text(l10n.common_save),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

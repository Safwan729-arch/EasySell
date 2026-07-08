import 'package:flutter/material.dart';

import '../../inventory/domain/product.dart';

/// Bottom sheet listing [products] with a name search; returns the chosen
/// product, or null if dismissed. Reused for the match chooser and manual pick.
Future<Product?> showProductPickerSheet(
  BuildContext context, {
  required List<Product> products,
  required String title,
}) {
  return showModalBottomSheet<Product>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => _ProductPickerSheet(products: products, title: title),
  );
}

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet({required this.products, required this.title});

  final List<Product> products;
  final String title;

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _q.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.products
        : widget.products
              .where((p) => p.name.toLowerCase().contains(q))
              .toList();
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
            widget.title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            autofocus: false,
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
              hintText: 'Search products',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: list.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = list[i];
                final subtitle = [
                  p.brand,
                  p.variant,
                ].where((s) => s != null && s.isNotEmpty).join(' · ');
                return ListTile(
                  title: Text(p.name),
                  subtitle: subtitle.isEmpty ? null : Text(subtitle),
                  onTap: () => Navigator.of(context).pop(p),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

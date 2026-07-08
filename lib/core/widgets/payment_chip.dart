import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Payment-method values rendered in the sales history. NOTE: payment method is
/// not yet persisted on `transactions` (would need a schema column) — the value
/// shown is a deterministic display placeholder derived from the transaction id.
enum PaymentMethod { cash, card, mobile }

/// Deterministic placeholder payment method for visual fidelity in the history
/// list. Replace with a real `payment_method` column when the backend supports
/// it (see plan §4).
PaymentMethod placeholderPaymentFor(String seed) {
  var hash = 0;
  for (final c in seed.codeUnits) {
    hash = (hash * 31 + c) & 0x7fffffff;
  }
  return PaymentMethod.values[hash % PaymentMethod.values.length];
}

/// Small tinted pill labelling a sale's payment method: Cash (green), Card
/// (blue), Mobile (purple).
class PaymentChip extends StatelessWidget {
  const PaymentChip({super.key, required this.method});

  final PaymentMethod method;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final (label, color) = switch (method) {
      PaymentMethod.cash => ('Cash', colors.positive),
      PaymentMethod.card => ('Card', Theme.of(context).colorScheme.primary),
      PaymentMethod.mobile => ('Mobile', const Color(0xFF7C3AED)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

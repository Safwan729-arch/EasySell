import 'package:freezed_annotation/freezed_annotation.dart';

part 'ledger_entry.freezed.dart';

/// The kind of ledger movement. The DB stores snake_case strings; the enum is
/// the app-side representation.
enum LedgerEntryType {
  creditSale('credit_sale'),
  payment('payment');

  const LedgerEntryType(this.dbValue);
  final String dbValue;

  static LedgerEntryType fromDb(String value) => switch (value) {
    'credit_sale' => LedgerEntryType.creditSale,
    'payment' => LedgerEntryType.payment,
    _ => throw ArgumentError('Unknown ledger entry_type: $value'),
  };
}

/// One immutable row of a customer's ledger — a credit sale (+) or a payment
/// (−). `amount` is always positive; [entryType] carries the sign.
@freezed
abstract class LedgerEntry with _$LedgerEntry {
  const LedgerEntry._();

  const factory LedgerEntry({
    required String id,
    required String customerId,
    required LedgerEntryType entryType,
    required double amount,
    String? saleGroupId,
    String? note,
    required DateTime createdAt,
  }) = _LedgerEntry;

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    // Block body (not `=>`) is required: freezed detects whether to wire up
    // its own generated fromJson/toJson based on arrow-vs-block syntax here,
    // regardless of what the arrow body calls. A block body opts this class
    // out of freezed's JSON codegen so our hand-written mapping (enum +
    // .toLocal()) is the only fromJson that exists.
    return LedgerEntry(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      entryType: LedgerEntryType.fromDb(json['entry_type'] as String),
      amount: (json['amount'] as num).toDouble(),
      saleGroupId: json['sale_group_id'] as String?,
      note: json['note'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}

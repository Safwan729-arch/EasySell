import 'package:freezed_annotation/freezed_annotation.dart';

part 'customer.freezed.dart';
part 'customer.g.dart';

/// A shop-scoped customer who may buy on credit. `name` and `phone` are
/// required (product decision); `note` is optional.
@freezed
abstract class Customer with _$Customer {
  const Customer._();

  const factory Customer({
    required String id,
    required String shopId,
    required String name,
    required String phone,
    String? note,
    DateTime? createdAt,
  }) = _Customer;

  factory Customer.fromJson(Map<String, dynamic> json) =>
      _$CustomerFromJson(json);
}

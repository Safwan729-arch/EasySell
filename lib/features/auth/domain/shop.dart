/// A shop — the tenancy boundary every other table is scoped to.
///
/// NOTE: interim plain-Dart model. The freezed + json_serializable pattern is
/// introduced in Milestone 3 with `Product` (the designated feature template);
/// this can be migrated to match once that pattern is established.
class Shop {
  const Shop({
    required this.id,
    required this.ownerId,
    required this.name,
    this.address,
    this.phone,
    this.currency = 'USD',
  });

  final String id;
  final String ownerId;
  final String name;
  final String? address;
  final String? phone;
  final String currency;

  /// Maps a Supabase row (snake_case keys) into a [Shop].
  factory Shop.fromMap(Map<String, dynamic> map) {
    return Shop(
      id: map['id'] as String,
      ownerId: map['owner_id'] as String,
      name: map['name'] as String,
      address: map['address'] as String?,
      phone: map['phone'] as String?,
      currency: (map['currency'] as String?) ?? 'USD',
    );
  }

  /// Payload for inserting a new shop. `id`/`created_at` are DB-generated;
  /// `owner_id` is set server-side by the caller from the authenticated user.
  Map<String, dynamic> toInsert({required String ownerId}) {
    return {
      'owner_id': ownerId,
      'name': name,
      if (address != null && address!.isNotEmpty) 'address': address,
      if (phone != null && phone!.isNotEmpty) 'phone': phone,
      'currency': currency,
    };
  }
}

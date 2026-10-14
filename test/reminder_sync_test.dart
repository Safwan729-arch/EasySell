import 'package:ai_shopkeeper/features/auth/data/auth_repository.dart';
import 'package:ai_shopkeeper/features/auth/domain/shop.dart';
import 'package:ai_shopkeeper/features/expiry/data/reminder_service.dart';
import 'package:ai_shopkeeper/features/expiry/domain/product_batch.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_prefs.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/expiry_providers.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/reminder_sync.dart';
import 'package:ai_shopkeeper/features/expiry/presentation/today_provider.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:ai_shopkeeper/features/inventory/presentation/inventory_controller.dart';
import 'package:ai_shopkeeper/shared/providers/locale_provider.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

class _FakeService implements ReminderService {
  final replaced = <List<ScheduledReminder>>[];
  int cancels = 0;

  @override
  Future<void> replaceAll(
    List<ScheduledReminder> reminders, {
    required String channelName,
  }) async => replaced.add(reminders);

  @override
  Future<void> cancelAll() async => cancels++;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<bool> notificationsEnabled() async => true;

  @override
  Stream<void> get taps => const Stream.empty();

  @override
  bool consumeLaunchTap() => false;
}

const _pepsi = Product(id: 'pepsi', shopId: 's1', name: 'Pepsi', quantity: 15);
final _batches = [
  ProductBatch(
    id: 'old',
    shopId: 's1',
    productId: 'pepsi',
    quantity: 5,
    receivedOn: DateTime(2026, 10, 1),
    expiryDate: DateTime(2026, 10, 20),
    expiredQty: 5,
  ),
];

Future<_FakeService> _sync({
  Shop? shop = const Shop(
    id: 's1',
    ownerId: 'o1',
    name: 'Shop',
    currency: 'BDT',
  ),
  ExpiryPrefs prefs = const ExpiryPrefs(),
  Locale locale = const Locale('en'),
}) async {
  final service = _FakeService();
  final c = ProviderContainer(
    overrides: [
      reminderServiceProvider.overrideWithValue(service),
      myShopProvider.overrideWith((ref) async => shop),
      productsStreamProvider.overrideWith((ref) => Stream.value([_pepsi])),
      batchesStreamProvider.overrideWith((ref) => Stream.value(_batches)),
      nowProvider.overrideWithValue(() => DateTime(2026, 10, 21, 8)),
      initialExpiryPrefsProvider.overrideWithValue(prefs),
      initialLocaleProvider.overrideWithValue(locale),
    ],
  );
  addTearDown(c.dispose);
  final sub = c.listen(reminderSyncProvider, (_, _) {});
  addTearDown(sub.close);
  // Signed out / switched off, the sync never watches these autoDispose
  // streams; hold them here so awaiting them below cannot dispose them.
  final products = c.listen(productsStreamProvider, (_, _) {});
  addTearDown(products.close);
  final batches = c.listen(batchesStreamProvider, (_, _) {});
  addTearDown(batches.close);
  await c.read(myShopProvider.future);
  await c.read(productsStreamProvider.future);
  await c.read(batchesStreamProvider.future);
  await Future<void>.delayed(Duration.zero);
  return service;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late String? previousLocale;
  setUp(() => previousLocale = Intl.defaultLocale);
  tearDown(() => Intl.defaultLocale = previousLocale);

  test('schedules the next days with the alert text', () async {
    final service = await _sync();
    final first = service.replaced.last.first;
    expect(first.at, DateTime(2026, 10, 21, 9));
    expect(first.title, 'Expiry check');
    expect(first.body, 'Expired: 5 Pepsi');
  });

  test('reminder text follows the app language', () async {
    final service = await _sync(locale: const Locale('bn'));
    final first = service.replaced.last.first;
    expect(first.title, 'মেয়াদ যাচাই');
    expect(first.body, 'মেয়াদোত্তীর্ণ: ৫ Pepsi');
  });

  test('signed out or switched off cancels everything', () async {
    expect((await _sync(shop: null)).cancels, greaterThan(0));
    expect(
      (await _sync(prefs: const ExpiryPrefs(remindersOn: false))).cancels,
      greaterThan(0),
    );
  });
}

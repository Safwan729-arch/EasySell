import 'package:ai_shopkeeper/features/cart/presentation/payment_method_controller.dart';
import 'package:ai_shopkeeper/features/customers/domain/customer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _rahim = Customer(id: 'c1', shopId: 's', name: 'Rahim', phone: '017');

void main() {
  late ProviderContainer c;
  setUp(() => c = ProviderContainer());
  tearDown(() => c.dispose());

  PaymentSelection read() => c.read(paymentMethodControllerProvider);
  PaymentMethodController notifier() =>
      c.read(paymentMethodControllerProvider.notifier);

  test('defaults to cash and is ready', () {
    expect(read().method, PaymentMethod.cash);
    expect(read().isReady, isTrue);
  });

  test('credit with no customer is not ready', () {
    notifier().setCredit();
    expect(read().method, PaymentMethod.credit);
    expect(read().customer, isNull);
    expect(read().isReady, isFalse);
  });

  test('choosing a customer makes credit ready', () {
    notifier().setCredit();
    notifier().chooseCustomer(_rahim);
    expect(read().customer, _rahim);
    expect(read().isReady, isTrue);
  });

  test('switching back to cash clears the customer and is ready', () {
    notifier().setCredit();
    notifier().chooseCustomer(_rahim);
    notifier().setCash();
    expect(read().method, PaymentMethod.cash);
    expect(read().customer, isNull);
    expect(read().isReady, isTrue);
  });

  test('digital is ready and needs no customer', () {
    notifier().setDigital();
    expect(read().method, PaymentMethod.digital);
    expect(read().customer, isNull);
    expect(read().isReady, isTrue);
  });

  test('switching from credit to digital clears the customer', () {
    notifier().setCredit();
    notifier().chooseCustomer(_rahim);
    notifier().setDigital();
    expect(read().method, PaymentMethod.digital);
    expect(read().customer, isNull);
  });

  test('reset returns to cash', () {
    notifier().setCredit();
    notifier().chooseCustomer(_rahim);
    notifier().reset();
    expect(read().method, PaymentMethod.cash);
    expect(read().customer, isNull);
  });
}

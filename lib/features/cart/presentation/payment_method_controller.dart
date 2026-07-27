import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../customers/domain/customer.dart';

/// How the current cart will be paid for.
enum PaymentMethod { cash, credit }

/// The cart's payment selection: the method and, for credit, the chosen
/// customer. A credit sale is only [isReady] once a customer is chosen.
class PaymentSelection {
  const PaymentSelection({required this.method, this.customer});
  const PaymentSelection.cash() : this(method: PaymentMethod.cash);

  final PaymentMethod method;
  final Customer? customer;

  bool get isReady =>
      method == PaymentMethod.cash || customer != null;
}

class PaymentMethodController extends Notifier<PaymentSelection> {
  @override
  PaymentSelection build() => const PaymentSelection.cash();

  void setCash() => state = const PaymentSelection.cash();

  void setCredit() =>
      state = const PaymentSelection(method: PaymentMethod.credit);

  void chooseCustomer(Customer customer) => state =
      PaymentSelection(method: PaymentMethod.credit, customer: customer);

  void reset() => state = const PaymentSelection.cash();
}

final paymentMethodControllerProvider =
    NotifierProvider<PaymentMethodController, PaymentSelection>(
      PaymentMethodController.new,
    );

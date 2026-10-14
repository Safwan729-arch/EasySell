import 'package:ai_shopkeeper/features/cart/domain/cart_line.dart';
import 'package:ai_shopkeeper/features/cart/domain/cart_math.dart';
import 'package:ai_shopkeeper/features/inventory/domain/product.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pepsi = Product(id: 'p1', shopId: 's1', name: 'Pepsi', quantity: 15);

  test('remaining stock can be measured against good stock', () {
    final lines = [CartLine(product: pepsi, quantity: 4)];
    expect(remainingStockForLines(lines, pepsi), 11);
    expect(remainingStockForLines(lines, pepsi, stock: 10), 6);
    expect(remainingStockForLines(lines, pepsi, stock: 3), 0);
  });
}

import 'package:ai_shopkeeper/features/scan/domain/scan_decision.dart';
import 'package:ai_shopkeeper/features/scan/presentation/scan_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ScanOutcome outcome({String? b, String? n, String? s}) => ScanOutcome(
    action: ScanAction.noMatch,
    products: const [],
    readBrand: b,
    readName: n,
    readSize: s,
  );

  test('readLabel joins non-empty parts with a middot', () {
    expect(outcome(b: 'Pepsi', s: '1L').readLabel, 'Pepsi · 1L');
    expect(outcome(b: 'Pepsi', n: 'Cola', s: '500ml').readLabel, 'Pepsi · Cola · 500ml');
  });

  test('readLabel is null when nothing was read', () {
    expect(outcome().readLabel, isNull);
    expect(outcome(b: '   ', n: '').readLabel, isNull);
  });
}

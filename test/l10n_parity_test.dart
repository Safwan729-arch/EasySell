import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every translatable key in the English template must have a Bengali
/// translation and vice-versa. Guards against half-translated screens.
void main() {
  Set<String> keysOf(String path) {
    final map = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    // Skip @@locale and @-metadata entries.
    return map.keys.where((k) => !k.startsWith('@')).toSet();
  }

  test('app_en.arb and app_bn.arb expose identical key sets', () {
    final en = keysOf('lib/l10n/app_en.arb');
    final bn = keysOf('lib/l10n/app_bn.arb');
    expect(en.difference(bn), isEmpty,
        reason: 'English keys missing a Bengali translation');
    expect(bn.difference(en), isEmpty,
        reason: 'Bengali keys with no English template entry');
  });
}

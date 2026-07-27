import 'package:ai_shopkeeper/core/l10n/enum_labels.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dashboard 7-day chart's day labels. Bengali single-letter initials
/// collide (বুধ/বৃহস্পতি → ব, শুক্র/শনি → শ), so Bengali uses distinct short
/// forms. These tests lock in that the seven labels are all distinct and map to
/// the right weekday, guarding against a regression back to `.substring(0, 1)`.
void main() {
  // A known week: 2024-07-08 is a Monday, so +0..+6 walks Mon → Sun.
  final monday = DateTime(2024, 7, 8);
  List<String> week(Locale l) =>
      [for (var i = 0; i < 7; i++) weekdayBarLabel(l, monday.add(Duration(days: i)))];

  test('Bengali weekday labels are all distinct (no collisions)', () {
    final labels = week(const Locale('bn'));
    expect(labels.toSet().length, 7, reason: 'each day must be unique');
  });

  test('Bengali weekday labels map Mon→Sun in order', () {
    expect(
      week(const Locale('bn')),
      ['সো', 'ম', 'বু', 'বৃ', 'শু', 'শ', 'র'],
    );
  });

  test('English keeps conventional single initials', () {
    expect(week(const Locale('en')), ['M', 'T', 'W', 'T', 'F', 'S', 'S']);
  });
}

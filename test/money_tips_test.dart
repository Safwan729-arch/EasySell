import 'package:ai_shopkeeper/core/error/failure.dart';
import 'package:ai_shopkeeper/core/error/result.dart';
import 'package:ai_shopkeeper/features/finance/data/money_tips_repository.dart';
import 'package:ai_shopkeeper/features/finance/domain/finance_health.dart';
import 'package:ai_shopkeeper/features/finance/presentation/money_tips_controller.dart';
import 'package:ai_shopkeeper/features/finance/presentation/money_tips_facts.dart';
import 'package:ai_shopkeeper/l10n/app_localizations_en.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeTipsRepo implements MoneyTipsRepository {
  FakeTipsRepo(this.result);

  Result<List<String>> result;
  int calls = 0;
  Map<String, dynamic>? lastFacts;
  String? lastLang;

  @override
  Future<Result<List<String>>> fetch({
    required String lang,
    required Map<String, dynamic> facts,
  }) async {
    calls++;
    lastLang = lang;
    lastFacts = facts;
    return result;
  }
}

FinanceHealth _h({double cash = 500, int overdue = 0}) => FinanceHealth(
  cashSales7d: cash,
  digitalSales7d: 0,
  creditSales7d: 0,
  collected7d: 0,
  restockSpend7d: 900,
  salesWeek: 0,
  salesPrevWeek: 0,
  owedNow: 0,
  owedWeekAgo: 0,
  overdueCount: overdue,
  overdueTopName: overdue > 0 ? 'Rahim' : null,
  overdueTopBalance: overdue > 0 ? 1200 : null,
  overdueTopDays: overdue > 0 ? 34 : null,
  sales90d: 0,
  profit90d: 0,
  digitalSales90d: 0,
  restockSpend90d: 0,
  activeWeeks12: 0,
  tradingDays: 10,
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('facts', () {
    final l10n = AppLocalizationsEn();

    test('carry the numbers and the same sentences the card shows', () {
      final f = moneyTipsFacts(
        health: _h(overdue: 2),
        l10n: l10n,
        currency: 'USD',
      );
      final week = f['last_7_days'] as Map<String, dynamic>;
      expect(week['money_in'], r'$500');
      expect(week['money_out_restocks_only'], r'$900');
      expect(week['net'], r'-$400');
      final warnings = f['warnings'] as List;
      expect(
        warnings.first,
        r'Rahim owes $1,200.00 for 34 days and 1 more customer is late',
      );
      expect(
        warnings,
        contains(r'Restocks cost $400.00 more than the money that came in'),
      );
      final financing = f['financing_examples'] as List;
      expect(financing, hasLength(4));
      expect((financing.first as Map)['fits'], isFalse);
    });
  });

  group('controller', () {
    late FakeTipsRepo repo;
    late ProviderContainer c;

    setUp(() {
      repo = FakeTipsRepo(const Result.success(['Collect from Rahim.']));
      c = ProviderContainer(
        overrides: [moneyTipsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
    });

    Future<void> ask(String key) => c
        .read(moneyTipsProvider.notifier)
        .ask(key: key, lang: 'en', facts: const {'a': 1});

    test('a tap fetches tips; the same numbers never call twice', () async {
      await ask('k1');
      expect(c.read(moneyTipsProvider), isA<TipsReady>());
      expect((c.read(moneyTipsProvider) as TipsReady).tips, [
        'Collect from Rahim.',
      ]);
      await ask('k1');
      expect(repo.calls, 1);
    });

    test('new numbers ask again', () async {
      await ask('k1');
      await ask('k2');
      expect(repo.calls, 2);
      expect((c.read(moneyTipsProvider) as TipsReady).key, 'k2');
    });

    test('a failure is reported for that key, and retry works', () async {
      repo.result = const Result.failure(DatabaseFailure('x'));
      await ask('k1');
      expect(c.read(moneyTipsProvider), isA<TipsFailed>());
      repo.result = const Result.success(['ok']);
      await ask('k1');
      expect(c.read(moneyTipsProvider), isA<TipsReady>());
    });

    test('the answer survives a restart (saved on the phone)', () async {
      await ask('k1');
      final fresh = ProviderContainer(
        overrides: [moneyTipsRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(fresh.dispose);
      fresh.read(moneyTipsProvider);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final s = fresh.read(moneyTipsProvider);
      expect(s, isA<TipsReady>());
      expect((s as TipsReady).key, 'k1');
      await fresh
          .read(moneyTipsProvider.notifier)
          .ask(key: 'k1', lang: 'en', facts: const {});
      expect(repo.calls, 1);
    });
  });

  test('the key changes with the day, language and numbers', () {
    final d = DateTime(2026, 10, 18);
    final base = moneyTipsKey(d, 'en', const {'in': r'$5'});
    expect(moneyTipsKey(d, 'en', const {'in': r'$5'}), base);
    expect(
      moneyTipsKey(DateTime(2026, 10, 19), 'en', const {'in': r'$5'}),
      isNot(base),
    );
    expect(moneyTipsKey(d, 'bn', const {'in': r'$5'}), isNot(base));
    expect(moneyTipsKey(d, 'en', const {'in': r'$6'}), isNot(base));
  });
}

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../expiry/domain/expiry_dates.dart';
import '../data/money_tips_repository.dart';

/// Which tips these are for: the day, the language and every number Gemini
/// was shown. A new sale changes the numbers, so old advice is not passed off
/// as current -- the card offers to ask again instead.
String moneyTipsKey(DateTime today, String lang, Map<String, dynamic> facts) =>
    '${ymd(today)}|$lang|${jsonEncode(facts)}';

sealed class MoneyTipsState {
  const MoneyTipsState();
}

class TipsIdle extends MoneyTipsState {
  const TipsIdle();
}

class TipsLoading extends MoneyTipsState {
  const TipsLoading(this.key);

  final String key;
}

class TipsReady extends MoneyTipsState {
  const TipsReady(this.key, this.tips);

  final String key;
  final List<String> tips;
}

class TipsFailed extends MoneyTipsState {
  const TipsFailed(this.key);

  final String key;
}

const _kCache = 'money_tips_cache';

/// Gemini is only called when the seller taps, and never twice for the same
/// key: the last answer is kept on the phone, so reopening the app the same
/// day with the same numbers shows it again for free.
class MoneyTipsController extends Notifier<MoneyTipsState> {
  @override
  MoneyTipsState build() {
    _restore();
    return const TipsIdle();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCache);
      if (raw == null) return;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      final tips = [for (final t in m['tips'] as List) t as String];
      // A tap that already started wins over the saved copy.
      if (state is TipsIdle) state = TipsReady(m['key'] as String, tips);
    } catch (_) {
      // A broken cache only costs one extra tap.
    }
  }

  Future<void> ask({
    required String key,
    required String lang,
    required Map<String, dynamic> facts,
  }) async {
    if (state is TipsLoading) return;
    if (state case TipsReady(key: final k) when k == key) return;
    state = TipsLoading(key);
    final r = await ref
        .read(moneyTipsRepositoryProvider)
        .fetch(lang: lang, facts: facts);
    r.when(
      success: (tips) {
        state = TipsReady(key, tips);
        _save(key, tips);
      },
      failure: (_) => state = TipsFailed(key),
    );
  }

  Future<void> _save(String key, List<String> tips) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCache, jsonEncode({'key': key, 'tips': tips}));
    } catch (_) {}
  }
}

final moneyTipsProvider = NotifierProvider<MoneyTipsController, MoneyTipsState>(
  MoneyTipsController.new,
);

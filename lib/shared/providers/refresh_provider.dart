import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A simple tick bumped whenever data that analytics depends on changes (e.g. a
/// sale/restock is recorded). Analytics providers `watch` this so dashboards
/// refresh without coupling the transactions feature to the analytics feature.
class DataRefresh extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final dataRefreshProvider = NotifierProvider<DataRefresh, int>(DataRefresh.new);

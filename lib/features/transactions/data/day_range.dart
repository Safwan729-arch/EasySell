/// The UTC half-open range `[startUtc, endUtc)` that covers the local calendar
/// day of [day]. The time component of [day] is ignored. Used to bound a
/// "sales on this day" query so it can never leak into an adjacent day.
({DateTime startUtc, DateTime endUtc}) dayRangeUtc(DateTime day) {
  final startLocal = DateTime(day.year, day.month, day.day);
  final endLocal = startLocal.add(const Duration(days: 1));
  return (startUtc: startLocal.toUtc(), endUtc: endLocal.toUtc());
}

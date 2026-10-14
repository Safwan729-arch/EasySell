/// Local calendar-date helpers for the expiry feature.
///
/// Every date here is the PHONE's local date (spec §3.4). The server's
/// `current_date` is UTC, which in Bangladesh (UTC+6) is still "yesterday"
/// from midnight to 6 AM -- that would stretch a 5-day shelf life to 6 and move
/// the warning a day.
library;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole calendar days from [from] to [to]; negative when [to] is earlier.
/// Done in UTC so a daylight-saving change can never make a day 23 hours.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

/// `yyyy-MM-dd`, the wire format of a Postgres `date`.
String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

enum OddDate { none, past, farFuture }

/// Flags an expiry date worth a second look (spec §5 "Odd dates"): one that
/// has already passed, or one more than five years ahead (a mistyped year).
/// Both are still allowed -- the UI only asks for confirmation.
OddDate classifyExpiryDate(DateTime picked, DateTime today) {
  final p = dateOnly(picked);
  final t = dateOnly(today);
  if (p.isBefore(t)) return OddDate.past;
  if (p.isAfter(DateTime(t.year + 5, t.month, t.day))) return OddDate.farFuture;
  return OddDate.none;
}

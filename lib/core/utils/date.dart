/// Day-boundary helpers. Tasks and habits both key their per-day records by a
/// stable "yyyy-mm-dd" string so "today" means since-local-midnight and history
/// buckets line up regardless of time zone arithmetic.
abstract final class DayKey {
  /// The local-calendar key for [when], e.g. "2026-06-01".
  static String of(DateTime when) {
    final y = when.year.toString().padLeft(4, '0');
    final m = when.month.toString().padLeft(2, '0');
    final d = when.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// The "yyyy-mm" prefix for [when], used to sum a month's per-day records
  /// (a day key starts with its month prefix).
  static String monthPrefix(DateTime when) {
    final y = when.year.toString().padLeft(4, '0');
    final m = when.month.toString().padLeft(2, '0');
    return '$y-$m';
  }

  /// Keys for the last [count] days ending today (oldest first), inclusive.
  /// Used by the "last 10 days" row.
  static List<String> lastDays(int count, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return List.generate(
      count,
      (i) => of(today.subtract(Duration(days: count - 1 - i))),
    );
  }
}

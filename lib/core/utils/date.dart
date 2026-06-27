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

  /// Parse a "yyyy-mm-dd" key back to a local [DateTime] (midnight).
  static DateTime parse(String dayKey) {
    final p = dayKey.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  static const _weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  /// Full weekday name for [DateTime.weekday] (1 = Monday).
  static String weekday(int w) => _weekdays[w - 1];

  /// Full month name for a 1-based month number.
  static String monthName(int m) => _months[m - 1];

  /// Day number with its ordinal suffix: 1st, 2nd, 3rd, 4th … 11th, 21st, 31st.
  /// 11/12/13 always take "th".
  static String ordinalDay(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    return switch (day % 10) {
      1 => '${day}st',
      2 => '${day}nd',
      3 => '${day}rd',
      _ => '${day}th',
    };
  }
}

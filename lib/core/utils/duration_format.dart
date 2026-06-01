/// Formatting helpers for the time figures that sit at the centre of the ring
/// and across feed cards. Effort is the content, so these read naturally
/// ("2h 15m", "13 hrs · today") rather than as raw clock strings.
abstract final class DurationFormat {
  /// Compact session length, e.g. "2h 15m", "45m", "0m".
  static String hm(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  /// Live timer readout "H:MM:SS" / "M:SS" for the running stopwatch.
  static String stopwatch(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '$h:${two(m)}:${two(s)}';
    return '$m:${two(s)}';
  }

  /// Rounded whole-hours figure for the ring centre, e.g. "13 hrs".
  /// Uses "hr" for exactly one hour.
  static String hours(Duration d) {
    final whole = d.inMinutes / 60.0;
    final rounded = whole.round();
    return rounded == 1 ? '1 hr' : '$rounded hrs';
  }
}

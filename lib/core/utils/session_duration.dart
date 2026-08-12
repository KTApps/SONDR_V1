/// Formats a whole-second session length as a compact human string
/// ("1h 30m", "59m", "0m"), rounding a trailing 30-or-more seconds **up** to the
/// next minute — so 3570s (59m30s) reads "1h", not "59m". Rounding happens once,
/// on the total seconds, before splitting into hours + minutes, so it never
/// produces "60m".
String formatSessionDuration(int seconds) {
  final rem = seconds % 60;
  final minutesFloor = seconds ~/ 60;
  final totalMinutes = rem >= 30 ? minutesFloor + 1 : minutesFloor;
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h > 0 && m > 0) return '${h}h ${m}m';
  if (h > 0) return '${h}h';
  if (m > 0) return '${m}m';
  return '0m';
}

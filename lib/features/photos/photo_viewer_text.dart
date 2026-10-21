import '../../core/utils/date.dart';
import 'models/photo.dart';

/// The three lines under a photo in the viewer, as plain strings so they
/// can be checked without a widget. A fragment whose data a photo does not
/// carry is left out — an old photo without a session length is the task
/// alone, never "Piano · 0m".

/// "45m", "1h 20m", "2h". Null for nothing or less than a minute.
String? sessionLength(int seconds) {
  if (seconds < 60) return null;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

/// Line 1: "`<task>` · `<session length>`", or the task alone.
String viewerLine1(Photo photo) {
  final length = sessionLength(photo.sessionSeconds);
  return length == null ? photo.taskName : '${photo.taskName} · $length';
}

/// "Tue 14 Oct" — short weekday and month, no year.
String viewerDate(DateTime when) {
  final weekday = DayKey.weekday(when.weekday).substring(0, 3);
  final month = DayKey.monthName(when.month).substring(0, 3);
  return '$weekday ${when.day} $month';
}

/// Line 2: "`<Tue 14 Oct, 9:12 pm>` · `<Nh>` on `<task>`". [time] formats the
/// clock the way the device does (12 or 24 hour) — that is the one part a
/// string cannot decide for itself. The hours are the task's cumulative total
/// at capture, whole; "<1h" under an hour; left out when unknown.
String viewerLine2(Photo photo, {required String Function(DateTime) time}) {
  final when = photo.capturedAt;
  final stamp = '${viewerDate(when)}, ${time(when)}';
  final cum = photo.cumulativeSeconds;
  if (cum == null) return stamp;
  final hours = cum ~/ 3600;
  final n = hours < 1 ? '<1h' : '${hours}h';
  return '$stamp · $n on ${photo.taskName}';
}

/// Line 3, only for a photo that marks a crossing: "Milestone photo · 20h".
String? viewerLine3(Photo photo) {
  final hours = photo.milestoneHours;
  if (hours == null || hours <= 0) return null;
  return 'Milestone photo · ${hours}h';
}

/// "3 of 7". Null for a set of one.
String? viewerCounter(int index, int count) =>
    count > 1 ? '${index + 1} of $count' : null;

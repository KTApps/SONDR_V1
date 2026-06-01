import '../../../core/utils/date.dart';

/// A single timed pursuit (e.g. Spanish, Piano, Golf). Tasks are
/// architecturally separate from habits — no shared logic, no foreign keys.
///
/// Effort is stored as accumulated seconds, kept per day so "today" means time
/// logged since local midnight and the per-day history (last-10-days, calendar)
/// falls out for free. The task fills toward its active milestone: the first at
/// 20 hours, then every 20 hours, tying to the 20-hour competence philosophy.
class Task {
  const Task({
    required this.id,
    required this.name,
    this.secondsByDay = const {},
  });

  final String id;
  final String name;

  /// Seconds logged on each calendar day, keyed by [DayKey]. The map is the
  /// source of truth; totals and "today" derive from it.
  final Map<String, int> secondsByDay;

  /// Hours per milestone band — first competence milestone and the cadence
  /// thereafter (20h, 40h, 60h, ...).
  static const int milestoneStepHours = 20;
  static const int _stepSeconds = milestoneStepHours * 3600;

  /// Lifetime seconds accumulated across all days.
  int get totalSeconds =>
      secondsByDay.values.fold(0, (sum, s) => sum + s);

  Duration get total => Duration(seconds: totalSeconds);

  /// Seconds logged today (since local midnight) for [now].
  int todaySeconds(DateTime now) => secondsByDay[DayKey.of(now)] ?? 0;

  Duration todayDuration(DateTime now) => Duration(seconds: todaySeconds(now));

  /// Seconds logged across the calendar month containing [now].
  int monthSeconds(DateTime now) {
    final prefix = DayKey.monthPrefix(now);
    var sum = 0;
    secondsByDay.forEach((day, secs) {
      if (day.startsWith(prefix)) sum += secs;
    });
    return sum;
  }

  Duration monthDuration(DateTime now) => Duration(seconds: monthSeconds(now));

  /// 0..1 progress toward the FIRST 20-hour milestone, clamped (so a task past
  /// 20h reads as full). This is the per-task bar shown in the dropdown — the
  /// only place milestone progress appears.
  double get firstMilestoneProgress =>
      (totalSeconds / _stepSeconds).clamp(0.0, 1.0);

  /// How many 20-hour milestones have been reached so far.
  int get milestonesReached => totalSeconds ~/ _stepSeconds;

  /// The target hours of the milestone currently being filled toward
  /// (20, 40, 60, ...).
  int get activeMilestoneHours => (milestonesReached + 1) * milestoneStepHours;

  /// 0..1 progress within the current milestone band — what the outer ring
  /// fills. Total accumulated time drives this (not just today's), so the ring
  /// reflects the real climb toward the next milestone.
  double get milestoneProgress {
    final intoBand = totalSeconds - (milestonesReached * _stepSeconds);
    return intoBand / _stepSeconds;
  }

  /// Returns a copy with [extraSeconds] added to [day]'s tally.
  Task addingSeconds(int extraSeconds, DateTime day) {
    if (extraSeconds <= 0) return this;
    final key = DayKey.of(day);
    final next = Map<String, int>.from(secondsByDay);
    next[key] = (next[key] ?? 0) + extraSeconds;
    return Task(id: id, name: name, secondsByDay: next);
  }
}

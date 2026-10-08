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
    this.archived = false,
  });

  final String id;
  final String name;

  /// Seconds logged on each calendar day, keyed by [DayKey]. The map is the
  /// source of truth; totals and "today" derive from it.
  final Map<String, int> secondsByDay;

  /// Put away, not deleted.
  ///
  /// An archived task disappears from the places you CHOOSE a task — the
  /// dropdown, Profile's in-progress strip — and nowhere else. Every second it
  /// logged is still logged: the calendar, the day detail and the Milestones
  /// page are untouched, because archiving is a statement about what you are
  /// working on now, never about what you did.
  ///
  /// **Additive and forward-only.** A document written before the field
  /// existed has no `archived` key and reads back false.
  final bool archived;

  /// Hours per milestone band — first competence milestone and the cadence
  /// thereafter (20h, 40h, 60h, ...).
  static const int milestoneStepHours = 20;
  static const int _stepSeconds = milestoneStepHours * 3600;

  /// Lifetime seconds accumulated across all days.
  int get totalSeconds =>
      secondsByDay.values.fold(0, (sum, s) => sum + s);

  Duration get total => Duration(seconds: totalSeconds);

  /// Whole hours accumulated, always rounded DOWN.
  ///
  /// Never round this up: at 19h59m a rounded figure reads "20h" beside a ring
  /// that has not reset, claiming a milestone that has not been reached. The
  /// figure may understate the climb; it must never overstate it.
  int get wholeHours => total.inHours;

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

  /// How many 20-hour milestones have been reached so far.
  int get milestonesReached => totalSeconds ~/ _stepSeconds;

  /// The target hours of the milestone currently being filled toward
  /// (20, 40, 60, ...).
  int get activeMilestoneHours => (milestonesReached + 1) * milestoneStepHours;

  /// 0..1 progress within the current 20-hour block — what every milestone
  /// ring and bar in the app fills by (the profile tiles and the task dropdown
  /// pills), so a ring means the same thing everywhere.
  ///
  /// Total accumulated time drives this, not just today's, and it **resets to
  /// zero on each milestone**: the climb starts again toward the next block.
  /// A task at exactly 20h therefore reads empty, not full.
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
    return Task(
      id: id,
      name: name,
      secondsByDay: next,
      archived: archived,
    );
  }

  /// Returns a copy archived (or restored). Carries the history across —
  /// putting a task away must not touch a single logged second.
  Task archivedAs(bool value) => Task(
        id: id,
        name: name,
        secondsByDay: secondsByDay,
        archived: value,
      );

  /// Document body for persistence (the id is the doc key, kept separate).
  Map<String, dynamic> toMap() => {
        'name': name,
        'secondsByDay': secondsByDay,
        'archived': archived,
      };

  /// Rebuild from a stored document. Tolerates numbers coming back as `num`.
  factory Task.fromMap(String id, Map<String, dynamic> map) {
    final raw = map['secondsByDay'];
    final seconds = <String, int>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is num) seconds['$k'] = v.toInt();
      });
    }
    return Task(
      id: id,
      name: (map['name'] as String?) ?? '',
      secondsByDay: seconds,
      // Anything that is not an explicit `true` — a missing key on an older
      // document included — means active.
      archived: map['archived'] == true,
    );
  }
}

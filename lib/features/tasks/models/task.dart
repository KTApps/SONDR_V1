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
    this.creditedSessions = const [],
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

  /// The sessions already credited to this task, oldest first.
  ///
  /// Crediting is a read-modify-write: read the day's total, add the
  /// session, write the sum back. Offline, Firestore queues the write and
  /// applies it to its own cache straight away — so the write fails for
  /// want of an acknowledgement while the local copy already has the
  /// time. If the app re-reads the list before the owner tries again, and
  /// a relaunch is enough, the retry reads the credited total and adds the
  /// session on top of itself.
  ///
  /// So a credit is keyed. A session is identified by the instant it
  /// started; the document lives at `users/{uid}/tasks/{taskId}`, so the
  /// account and the task are already in the key's scope.
  ///
  /// **Additive and forward-only.** A document written before the field
  /// existed has no `creditedSessions` key and reads back empty, which
  /// only means its sessions cannot be recognised — never that time is
  /// lost or added.
  ///
  /// Bounded at [_creditMemory]: the window this has to cover is a failed
  /// credit and its retry — minutes, or days — and the document cannot be
  /// allowed to grow for the life of the task.
  final List<String> creditedSessions;

  /// Hours per milestone band — first competence milestone and the cadence
  /// thereafter (20h, 40h, 60h, ...).
  /// How many credited sessions a task remembers.
  static const int _creditMemory = 20;

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

  /// The key a session that began at [startedAt] is credited under.
  static String sessionKey(DateTime startedAt) =>
      '${startedAt.millisecondsSinceEpoch}';

  bool hasCredited(String session) => creditedSessions.contains(session);

  /// Returns a copy with [extraSeconds] credited to [day] — unless this
  /// session has been credited already, in which case it returns itself.
  ///
  /// Crediting the same session twice is never an addition. The caller
  /// still writes what comes back, so a retry puts the same numbers to
  /// the server and gets the acknowledgement it is waiting for.
  Task crediting(String session, int extraSeconds, DateTime day) {
    if (hasCredited(session)) return this;
    if (extraSeconds <= 0) return this;
    final seen = [...creditedSessions, session];
    return addingSeconds(extraSeconds, day)._remembering(
      seen.length <= _creditMemory
          ? seen
          : seen.sublist(seen.length - _creditMemory),
    );
  }

  Task _remembering(List<String> sessions) => Task(
        id: id,
        name: name,
        secondsByDay: secondsByDay,
        archived: archived,
        creditedSessions: sessions,
      );

  /// Returns a copy with [extraSeconds] added to [day]'s tally.
  ///
  /// Unkeyed, so it adds every time it is called. Everything that credits
  /// a real session goes through [crediting] instead; this is left for the
  /// debug tools that inject time no session ever ran.
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
      creditedSessions: creditedSessions,
    );
  }

  /// Returns a copy archived (or restored). Carries the history across —
  /// putting a task away must not touch a single logged second.
  Task archivedAs(bool value) => Task(
        id: id,
        name: name,
        secondsByDay: secondsByDay,
        archived: value,
        creditedSessions: creditedSessions,
      );

  /// Document body for persistence (the id is the doc key, kept separate).
  Map<String, dynamic> toMap() => {
        'name': name,
        'secondsByDay': secondsByDay,
        'archived': archived,
        'creditedSessions': creditedSessions,
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
      creditedSessions: [
        for (final s in (map['creditedSessions'] as List?) ?? const [])
          '$s',
      ],
    );
  }
}

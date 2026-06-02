import 'habit.dart';

/// One habit's state on one day: a *snapshot* of the habit (its id and name as
/// they were that day) plus whether it was checked off. Names are copied in,
/// not referenced, so renaming or removing a habit later never rewrites the
/// past.
class HabitTick {
  const HabitTick({
    required this.habitId,
    required this.name,
    required this.done,
  });

  final String habitId;
  final String name;
  final bool done;

  HabitTick copyWith({bool? done}) => HabitTick(
        habitId: habitId,
        name: name,
        done: done ?? this.done,
      );
}

/// A single day's habit record: the frozen list of habits that applied that day
/// and their completion. Checkmarks reset daily (each day has its own record);
/// the live list carries over. Past days are immutable — only today's record is
/// re-synced when the live list is edited.
class DailyHabits {
  const DailyHabits({required this.dayKey, required this.ticks});

  final String dayKey;
  final List<HabitTick> ticks;

  int get total => ticks.length;
  int get completed => ticks.where((t) => t.done).length;

  /// Inner-ring value: completed ÷ total (0 when there are no habits).
  double get progress => total == 0 ? 0 : completed / total;

  /// Returns a copy with one habit's done state flipped.
  DailyHabits withToggled(String habitId) => DailyHabits(
        dayKey: dayKey,
        ticks: [
          for (final t in ticks)
            t.habitId == habitId ? t.copyWith(done: !t.done) : t,
        ],
      );
}

/// The whole habits feature's state: the live ordered list plus every day's
/// record keyed by day. Today's record mirrors the live list; past records are
/// frozen snapshots.
class HabitsState {
  const HabitsState({required this.liveList, required this.days});

  final List<Habit> liveList;
  final Map<String, DailyHabits> days;
}

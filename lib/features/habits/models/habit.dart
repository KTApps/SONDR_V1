/// One entry in the user's single, global, ordered habit list (e.g. "Cold
/// shower"). Habits are architecturally separate from tasks — no shared logic,
/// no foreign keys. This is the *live* definition; what was actually true on a
/// given day is frozen in that day's snapshot (see [DailyHabits]).
class Habit {
  const Habit({required this.id, required this.name});

  final String id;
  final String name;
}

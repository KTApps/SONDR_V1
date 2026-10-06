import 'models/daily_habits.dart';

/// Data-access seam for habits. The app depends only on this interface; the
/// in-memory implementation backs it today and Firebase drops in later. Every
/// mutation returns the resulting [HabitsState] so callers don't re-fetch.
abstract interface class HabitsRepository {
  Future<HabitsState> fetch();

  /// Toggle a habit's completion for *today* only (past days are immutable).
  Future<HabitsState> toggle(String habitId);

  /// Append a new habit to the live list (applies from today forward).
  Future<HabitsState> addHabit(String name);

  /// Remove a habit from the live list. Past days keep it; today drops it.
  Future<HabitsState> removeHabit(String habitId);
}

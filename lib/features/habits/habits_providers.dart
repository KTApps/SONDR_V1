import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date.dart';
import 'habits_repository.dart';
import 'local_habits_repository.dart';
import 'models/daily_habits.dart';

/// The active [HabitsRepository]. Swapping to Firebase later is a one-line
/// change here.
final habitsRepositoryProvider = Provider<HabitsRepository>(
  (ref) => LocalHabitsRepository(),
);

/// Owns the habit list and per-day records, exposing the mutations the
/// checklist needs. Async to match the eventual backend; the local repository
/// resolves instantly.
class HabitsController extends AsyncNotifier<HabitsState> {
  @override
  Future<HabitsState> build() {
    return ref.watch(habitsRepositoryProvider).fetch();
  }

  HabitsRepository get _repo => ref.read(habitsRepositoryProvider);

  Future<void> toggle(String habitId) async {
    state = AsyncData(await _repo.toggle(habitId));
  }

  Future<void> addHabit(String name) async {
    if (name.trim().isEmpty) return;
    state = AsyncData(await _repo.addHabit(name));
  }

  Future<void> removeHabit(String habitId) async {
    state = AsyncData(await _repo.removeHabit(habitId));
  }
}

final habitsProvider =
    AsyncNotifierProvider<HabitsController, HabitsState>(HabitsController.new);

/// Today's habit record (the editable checklist source), or null while loading.
final todayHabitsProvider = Provider<DailyHabits?>((ref) {
  final state = ref.watch(habitsProvider).value;
  if (state == null) return null;
  return state.days[DayKey.of(DateTime.now())];
});

/// Inner-ring value: today's habits completed ÷ total. Reads from the real
/// record now (replaces the step-2 placeholder); the timer screen is unchanged.
final habitsTodayProgressProvider = Provider<double>((ref) {
  return ref.watch(todayHabitsProvider)?.progress ?? 0.0;
});

/// Day streak: the number of consecutive **fully-completed** days ending **at
/// yesterday** (a day is complete only if it had at least one habit and every
/// one was checked). It counts up to and including yesterday, so it is stable
/// all day and only changes at midnight — completing today's list does not bump
/// it until the day passes. A missing or incomplete day stops the count; an
/// empty-list day can't extend it. Editing the live list leaves it untouched
/// (it reads only frozen past days). Starts at 0.
final habitStreakProvider = Provider<int>((ref) {
  final state = ref.watch(habitsProvider).value;
  if (state == null) return 0;

  final now = DateTime.now();
  var cursor = DateTime(now.year, now.month, now.day)
      .subtract(const Duration(days: 1));
  var streak = 0;
  while (true) {
    final record = state.days[DayKey.of(cursor)];
    if (record == null || record.total == 0 || record.completed != record.total) {
      break;
    }
    streak++;
    cursor = DateTime(cursor.year, cursor.month, cursor.day)
        .subtract(const Duration(days: 1));
  }
  return streak;
});

import '../../core/utils/date.dart';
import 'habits_repository.dart';
import 'models/daily_habits.dart';
import 'models/habit.dart';

/// In-memory [HabitsRepository] for local-first development.
///
/// Source of truth is the live ordered list plus a per-day record map. The
/// immutable-history rule lives here: [_syncToday] rebuilds *only* today's
/// record from the live list (preserving which habits were already checked);
/// past days are never touched once written, so editing the list applies
/// forward only.
class LocalHabitsRepository implements HabitsRepository {
  LocalHabitsRepository() {
    _seed();
  }

  final List<Habit> _live = [];
  final Map<String, DailyHabits> _days = {};
  int _idCounter = 0;

  String _nextId() => 'habit_${_idCounter++}';

  void _seed() {
    _live.addAll([
      Habit(id: _nextId(), name: '6AM wake'),
      Habit(id: _nextId(), name: 'Make bed'),
      Habit(id: _nextId(), name: 'Cold shower'),
      Habit(id: _nextId(), name: 'Morning run'),
      Habit(id: _nextId(), name: '50 press ups'),
    ]);

    // Seed yesterday as a frozen snapshot (4 of 5 done) to exercise the
    // per-day history; it stays put when the live list later changes.
    final yesterday =
        DayKey.of(DateTime.now().subtract(const Duration(days: 1)));
    _days[yesterday] = DailyHabits(
      dayKey: yesterday,
      ticks: [
        for (var i = 0; i < _live.length; i++)
          HabitTick(
            habitId: _live[i].id,
            name: _live[i].name,
            done: i < 4,
          ),
      ],
    );

    // Today starts with the first two checked.
    _syncToday();
    final today = DayKey.of(DateTime.now());
    _days[today] = _days[today]!
        .withToggled(_live[0].id)
        .withToggled(_live[1].id);
  }

  /// Rebuild today's record from the live list, preserving done flags. New
  /// habits arrive unchecked; removed habits drop off; past days are untouched.
  void _syncToday() {
    final today = DayKey.of(DateTime.now());
    final existing = _days[today];
    final done = <String>{
      if (existing != null)
        for (final t in existing.ticks)
          if (t.done) t.habitId,
    };
    _days[today] = DailyHabits(
      dayKey: today,
      ticks: [
        for (final h in _live)
          HabitTick(habitId: h.id, name: h.name, done: done.contains(h.id)),
      ],
    );
  }

  HabitsState _snapshot() {
    _syncToday();
    return HabitsState(
      liveList: List.unmodifiable(_live),
      days: Map.unmodifiable(_days),
    );
  }

  @override
  Future<HabitsState> fetch() async => _snapshot();

  @override
  Future<HabitsState> toggle(String habitId) async {
    _syncToday();
    final today = DayKey.of(DateTime.now());
    _days[today] = _days[today]!.withToggled(habitId);
    return _snapshot();
  }

  @override
  Future<HabitsState> addHabit(String name) async {
    _live.add(Habit(id: _nextId(), name: name.trim()));
    return _snapshot();
  }

  @override
  Future<HabitsState> removeHabit(String habitId) async {
    _live.removeWhere((h) => h.id == habitId);
    return _snapshot();
  }
}

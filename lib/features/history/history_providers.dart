import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../habits/habits_providers.dart';
import '../habits/models/daily_habits.dart';
import '../tasks/tasks_providers.dart';

/// One task's logged time on a particular day.
class TaskTime {
  const TaskTime({required this.name, required this.seconds});
  final String name;
  final int seconds;
}

/// Everything needed to render a single past (or current) day: the per-task
/// split for the ring, a sorted breakdown of tasks worked, and that day's
/// frozen habit snapshot. Derived purely from the existing task/habit state —
/// history is just a read over data already stored per day.
class DayHistory {
  const DayHistory({
    required this.dayKey,
    required this.segments,
    required this.taskTimes,
    required this.habits,
  });

  final String dayKey;

  /// Per-task seconds in stable task order (zeros included), so segment colours
  /// stay consistent for a task across every day.
  final List<double> segments;

  /// Tasks with time that day, largest first.
  final List<TaskTime> taskTimes;

  /// That day's habit record (frozen snapshot), or null if none exists.
  final DailyHabits? habits;

  int get totalSeconds =>
      taskTimes.fold(0, (sum, t) => sum + t.seconds);

  bool get hasData =>
      totalSeconds > 0 || (habits != null && habits!.total > 0);
}

/// Read model for a given day key ("yyyy-mm-dd").
final dayHistoryProvider = Provider.family<DayHistory, String>((ref, dayKey) {
  final tasks = ref.watch(tasksProvider).value ?? const [];
  final habitsState = ref.watch(habitsProvider).value;

  final segments = <double>[
    for (final t in tasks) (t.secondsByDay[dayKey] ?? 0).toDouble(),
  ];
  final taskTimes = <TaskTime>[
    for (final t in tasks)
      if ((t.secondsByDay[dayKey] ?? 0) > 0)
        TaskTime(name: t.name, seconds: t.secondsByDay[dayKey]!),
  ]..sort((a, b) => b.seconds.compareTo(a.seconds));

  return DayHistory(
    dayKey: dayKey,
    segments: segments,
    taskTimes: taskTimes,
    habits: habitsState?.days[dayKey],
  );
});

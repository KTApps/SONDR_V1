import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';

/// Total effort across every task — the profile hero's headline figure. Sums
/// each task's lifetime seconds (tasks are the only source of timed effort).
final lifetimeDurationProvider = Provider<Duration>((ref) {
  final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
  final seconds = tasks.fold<int>(0, (sum, t) => sum + t.totalSeconds);
  return Duration(seconds: seconds);
});

/// Total 20-hour milestones reached across all tasks — "milestones hit" in the
/// effort summary. Each task contributes one per completed 20h band.
final milestonesReachedProvider = Provider<int>((ref) {
  final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
  return tasks.fold<int>(0, (sum, t) => sum + t.milestonesReached);
});

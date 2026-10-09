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

/// The next milestone anyone is going to reach, and how far off it is.
///
/// "Nearest" is the active task furthest through its current 20-hour band — a
/// task at 19h is one hour away and beats a task at 1h, whatever either has
/// logged in total. This drives the profile hero: the ring fills by
/// [progress], the subline reads off [hoursRemaining].
///
/// Hours remaining are rounded UP, so the line never promises a milestone
/// sooner than it will arrive and never reads "0h to go" while there is still
/// time on the clock. Archived tasks are not candidates — you are not climbing
/// toward a milestone on a task you have put away.
///
/// Null only when there is no active task at all, which is the hero's empty
/// state (a bare grey track).
typedef NextMilestone = ({Task task, double progress, int hoursRemaining});

final nextMilestoneProvider = Provider<NextMilestone?>((ref) {
  final tasks = ref.watch(activeTasksProvider);
  if (tasks.isEmpty) return null;

  var nearest = tasks.first;
  for (final t in tasks) {
    if (t.milestoneProgress > nearest.milestoneProgress) nearest = t;
  }

  final remaining = nearest.activeMilestoneHours * 3600 - nearest.totalSeconds;
  return (
    task: nearest,
    progress: nearest.milestoneProgress,
    hoursRemaining: (remaining / 3600).ceil(),
  );
});

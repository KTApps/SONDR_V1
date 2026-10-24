import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../habits/models/daily_habits.dart';
import '../tasks/models/task.dart';

/// One task, as the Home Screen widget needs it.
///
/// Flattened on purpose: the widget is a different process that may draw
/// while the app has not run for days, so it reads numbers rather than
/// recomputing them from a model it would have to keep in step.
@immutable
class WidgetTask {
  const WidgetTask({
    required this.id,
    required this.name,
    required this.today,
    required this.total,
    required this.progress,
    required this.lastTracked,
  });

  final String id;
  final String name;

  /// Seconds logged today, and over the task's life.
  final int today;
  final int total;

  /// 0..1 toward the next 20-hour milestone — [Task.milestoneProgress], so
  /// a ring in the widget means what every ring in the app means.
  final double progress;

  /// The last day this task was tracked, as a day key ('' if never). What
  /// the Automatic list is ordered by.
  final String lastTracked;

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'today': today,
    'total': total,
    'progress': progress,
    'last': lastTracked,
  };

  static WidgetTask of(Task task, DateTime now) => WidgetTask(
    id: task.id,
    name: task.name,
    today: task.todaySeconds(now),
    total: task.totalSeconds,
    progress: task.milestoneProgress,
    lastTracked: lastTrackedDay(task),
  );

  /// The latest day with any time on it. Day-level is enough: the list it
  /// orders is "the five you have been working on".
  static String lastTrackedDay(Task task) {
    var latest = '';
    task.secondsByDay.forEach((day, seconds) {
      if (seconds > 0 && day.compareTo(latest) > 0) latest = day;
    });
    return latest;
  }
}

/// Everything the Home Screen widget draws, in one document.
///
/// What it does NOT carry is the running session: that lives in the App
/// Group as `sondr.session` and the widget reads it there, exactly as the
/// Live Activity does. Two copies of a clock is two clocks.
@immutable
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.tasks,
    required this.segments,
    required this.habitsDone,
    required this.habitsTotal,
    required this.selectedTaskId,
  });

  /// Every unarchived task, in the app's own stable order.
  final List<WidgetTask> tasks;

  /// Today's seconds per task, in that same order — Home's dial, as the
  /// dial itself receives it.
  final List<int> segments;

  final int habitsDone;
  final int habitsTotal;

  /// What Home has selected, or '' for the collective view.
  final String selectedTaskId;

  /// The key it is written under, in the App Group beside the session.
  static const String key = 'sondr.widget';

  /// Bumped if the shape ever changes, so an old widget binary reading a
  /// new document can tell rather than guess.
  static const int version = 1;

  Map<String, Object?> toMap() => {
    'v': version,
    'tasks': [for (final t in tasks) t.toMap()],
    'segments': segments,
    'habitsDone': habitsDone,
    'habitsTotal': habitsTotal,
    'selected': selectedTaskId,
  };

  String toJson() => jsonEncode(toMap());

  static WidgetSnapshot of({
    required List<Task> tasks,
    required DailyHabits? habits,
    required String? selectedTaskId,
    required DateTime now,
  }) {
    final live = [for (final t in tasks) if (!t.archived) t];
    return WidgetSnapshot(
      tasks: [for (final t in live) WidgetTask.of(t, now)],
      segments: [for (final t in live) t.todaySeconds(now)],
      habitsDone: habits?.completed ?? 0,
      habitsTotal: habits?.total ?? 0,
      selectedTaskId: selectedTaskId ?? '',
    );
  }

  /// Two snapshots are the same when they would draw the same widget.
  @override
  bool operator ==(Object other) =>
      other is WidgetSnapshot && other.toJson() == toJson();

  @override
  int get hashCode => toJson().hashCode;
}

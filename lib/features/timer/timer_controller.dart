import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';

/// Lifecycle of the manual timer for the current session.
enum TimerStatus { idle, running, paused }

/// Immutable snapshot of the running timer. [sessionElapsed] is the time of the
/// in-progress session only; it is committed to the selected task's history on
/// [TimerController.stop].
class TimerState {
  const TimerState({
    this.status = TimerStatus.idle,
    this.sessionElapsed = Duration.zero,
  });

  final TimerStatus status;
  final Duration sessionElapsed;

  bool get isRunning => status == TimerStatus.running;

  /// True when a session exists (running or paused) — i.e. there is elapsed
  /// time not yet committed. Used to lock task switching mid-session.
  bool get isActive => status != TimerStatus.idle;

  TimerState copyWith({TimerStatus? status, Duration? sessionElapsed}) {
    return TimerState(
      status: status ?? this.status,
      sessionElapsed: sessionElapsed ?? this.sessionElapsed,
    );
  }
}

/// Drives the manual timer. Manual by design — no GPS or sensors; the user
/// starts, pauses, and stops to record real effort. While running, a 1-second
/// ticker advances [TimerState.sessionElapsed]; the screen folds that live time
/// into the dial so the ring climbs as you work. Stopping commits the session
/// to the currently selected task and resets to idle.
class TimerController extends Notifier<TimerState> {
  Timer? _ticker;

  @override
  TimerState build() {
    ref.onDispose(() => _ticker?.cancel());
    return const TimerState();
  }

  /// Start a new session or resume a paused one.
  void start() {
    if (state.isRunning) return;
    state = state.copyWith(status: TimerStatus.running);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(
        sessionElapsed: state.sessionElapsed + const Duration(seconds: 1),
      );
    });
  }

  /// Pause without committing — the elapsed time is kept.
  void pause() {
    if (!state.isRunning) return;
    _ticker?.cancel();
    state = state.copyWith(status: TimerStatus.paused);
  }

  /// Stop and commit the session's whole seconds to the selected task's history
  /// for today, then reset. Reports what was logged and whether the commit
  /// pushed the task across a 20-hour milestone, so the screen can celebrate.
  Future<StopOutcome> stop() async {
    _ticker?.cancel();
    final seconds = state.sessionElapsed.inSeconds;
    final task = ref.read(selectedTaskProvider);

    var milestoneHours = 0;
    var wasFirst = false;
    var totalHours = 0;
    var totalSeconds = 0;
    if (task != null && seconds > 0) {
      final before = task.milestonesReached;
      await ref
          .read(tasksProvider.notifier)
          .logSeconds(task.id, seconds, DateTime.now());
      final updated = ref
          .read(tasksProvider)
          .value
          ?.where((t) => t.id == task.id)
          .firstOrNull;
      final after = updated?.milestonesReached ?? before;
      totalSeconds = updated?.totalSeconds ?? 0;
      totalHours = (totalSeconds / 3600).round();
      if (after > before) {
        milestoneHours = after * Task.milestoneStepHours;
        wasFirst = before == 0;
      }
    }

    state = const TimerState();
    return StopOutcome(
      loggedSeconds: seconds,
      taskId: task?.id,
      taskName: task?.name,
      milestoneHours: milestoneHours == 0 ? null : milestoneHours,
      isFirstMilestone: wasFirst,
      totalHours: totalHours,
      totalSeconds: totalSeconds,
    );
  }
}

/// Result of stopping the timer: what was committed and, if the session pushed
/// the task past a 20-hour boundary, the milestone just reached.
class StopOutcome {
  const StopOutcome({
    required this.loggedSeconds,
    required this.taskId,
    required this.taskName,
    required this.milestoneHours,
    required this.isFirstMilestone,
    required this.totalHours,
    required this.totalSeconds,
  });

  final int loggedSeconds;

  /// The id of the task this session was credited to — null when no task was
  /// selected (so nothing was logged). Carried so a photo can attach to exactly
  /// the task that received the seconds, not a re-read of the selection.
  final String? taskId;

  final String? taskName;

  /// The milestone hours just crossed (20, 40, …), or null if none.
  final int? milestoneHours;

  /// True when [milestoneHours] is the task's very first milestone (20h).
  final bool isFirstMilestone;

  /// The task's lifetime hours after this session was committed — carried so a
  /// milestone post can show the real total.
  final int totalHours;

  /// The task's precise cumulative seconds after this session — snapshotted onto
  /// a kept photo as its [Photo.cumulativeSeconds] (the collage band key). 0 when
  /// no task was credited.
  final int totalSeconds;

  bool get reachedMilestone => milestoneHours != null;
}

final timerControllerProvider =
    NotifierProvider<TimerController, TimerState>(TimerController.new);

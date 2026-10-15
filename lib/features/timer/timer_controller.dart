import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';
import 'session_clock.dart';
import 'session_store.dart';

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
/// starts, pauses, and stops to record real effort.
///
/// Elapsed time is DERIVED from wall-clock timestamps, never accumulated by
/// the ticker. The ticker exists only to repaint once a second: it could
/// miss every tick for an hour and the answer would still be right. That is
/// the whole point — a ticker stops firing the moment iOS suspends the app,
/// so the old counter treated a locked phone as time that never happened.
///
/// The session is written to [SessionStore] whenever it changes, so iOS
/// reclaiming the app mid-session loses nothing: the next launch reads the
/// start time back and carries on.
class TimerController extends Notifier<TimerState> {
  Timer? _ticker;
  SessionClock? _clock;
  _Resync? _observer;

  DateTime _now() => ref.read(nowProvider)();
  SessionStore get _store => ref.read(sessionStoreProvider);

  @override
  TimerState build() {
    ref.onDispose(() {
      _ticker?.cancel();
      final observer = _observer;
      if (observer != null) {
        WidgetsBinding.instance.removeObserver(observer);
        _observer = null;
      }
    });
    // A session left running by a previous launch. Fire-and-forget: build
    // cannot wait, and an idle timer is the right thing to show until the
    // read lands.
    unawaited(restore());
    return const TimerState();
  }

  /// Pick up a session the last launch left behind.
  ///
  /// Public so the test for it does not have to fake a process death.
  Future<void> restore() async {
    if (_clock != null) return;
    final found = await _store.read();
    if (found == null || _clock != null) return;
    _clock = found;
    // Put the task back too. Selection is not persisted, so a restored
    // session would otherwise be running against nothing and Stop would
    // credit no task — the time would come back and then go nowhere.
    final taskId = found.taskId;
    if (taskId != null) {
      ref.read(selectedTaskIdProvider.notifier).select(taskId);
    }
    if (!found.isPaused) _startTicking();
    // Nothing has changed about the session, so do not write it back.
    _publish(persist: false);
  }

  /// Start a new session, or resume a paused one.
  void start() {
    if (state.isRunning) return;
    final now = _now();
    _clock =
        _clock?.resume(now) ??
        SessionClock(
          startedAt: now,
          // The id, not the task: selectedTaskProvider resolves against the
          // loaded list, which is still arriving on a cold start, and a
          // session that began before it landed would record no task.
          taskId: ref.read(selectedTaskIdProvider),
        );
    _startTicking();
    _publish();
  }

  /// Pause without committing — the elapsed time is kept.
  void pause() {
    if (!state.isRunning) return;
    _ticker?.cancel();
    _clock = _clock?.pause(_now());
    _publish();
  }

  void _startTicking() {
    _ticker?.cancel();
    // Repaint, not count: every tick re-reads the clock.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _publish());
    final observer = _observer ??= _Resync(_publish);
    WidgetsBinding.instance.addObserver(observer);
  }

  /// Re-read the clock now, as the app coming back from the background
  /// does. Named for the test, because simulating a lifecycle event is a
  /// worse way to ask the same question.
  @visibleForTesting
  void resyncForTest() => _publish();

  /// Push the clock's current answer into state, and keep the stored copy up
  /// to date.
  void _publish({bool persist = true}) {
    final clock = _clock;
    if (clock == null) {
      state = const TimerState();
      return;
    }
    state = TimerState(
      status: clock.isPaused ? TimerStatus.paused : TimerStatus.running,
      sessionElapsed: clock.elapsedAt(_now()),
    );
    if (persist) unawaited(_store.write(clock));
  }

  Future<StopOutcome> stop() async {
    _ticker?.cancel();
    // The clock, not the last tick: a session stopped straight after the
    // phone was unlocked must count the time the screen was dark, and the
    // ticker has not run since it went off.
    final seconds = (_clock?.elapsedAt(_now()) ?? state.sessionElapsed)
        .inSeconds;
    final task = ref.read(selectedTaskProvider);

    var milestoneHours = 0;
    var wasFirst = false;
    var totalHours = 0;
    var totalSeconds = 0;
    if (task != null && seconds > 0) {
      final before = task.milestonesReached;
      await ref
          .read(tasksProvider.notifier)
          .logSeconds(task.id, seconds, _now());
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

    _clock = null;
    unawaited(_store.clear());
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

/// Re-reads the clock the instant the app comes back, so the display does
/// not wait up to a second to admit how long the phone was locked.
class _Resync extends WidgetsBindingObserver {
  _Resync(this.onResumed);

  final VoidCallback onResumed;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResumed();
  }
}

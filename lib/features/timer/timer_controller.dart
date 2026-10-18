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

  /// The last thing written to the store, so an unchanged clock is not
  /// written again.
  String? _written;

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
    _written = found.encode();
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

  /// The running session, for anything that needs more than its elapsed
  /// time — when it started, what it is for, whether to ask about it.
  SessionClock? get clock => _clock;

  /// Whether to ask "Still going?" right now.
  bool get shouldAskStillGoing => _clock?.shouldAsk(_now()) ?? false;

  /// Record that someone has said the session is real.
  void confirmStillGoing() {
    final clock = _clock;
    if (clock == null) return;
    _clock = clock.confirmedNow(_now());
    _publish();
  }

  /// Move the running session's start back by [by], for testing the
  /// "Still going?" prompt without sitting through three hours.
  ///
  /// DEBUG_TOOLS only — the one caller is behind that gate, so this is
  /// unreachable in a release build.
  void backdateForDebug(Duration by) {
    final clock = _clock;
    final now = _now();
    _clock = clock == null
        ? SessionClock(
            startedAt: now.subtract(by),
            taskId: ref.read(selectedTaskIdProvider),
          )
        : SessionClock(
            startedAt: clock.startedAt.subtract(by),
            pausedTotal: clock.pausedTotal,
            pausedAt: clock.pausedAt,
            taskId: clock.taskId,
            taskName: clock.taskName,
            taskSecondsBefore: clock.taskSecondsBefore,
            confirmedAt: clock.confirmedAt,
          );
    if (_clock!.isPaused) {
      _publish();
    } else {
      _startTicking();
      _publish();
    }
  }

  /// Re-read the clock now, as the app coming back from the background
  /// does. Named for the test, because simulating a lifecycle event is a
  /// worse way to ask the same question.
  @visibleForTesting
  void resyncForTest() => _publish();

  /// Fill in what the Live Activity needs and the app does not.
  ///
  /// A session can start on a cold launch before the task list has arrived,
  /// so the name and the task's prior seconds are picked up the first time
  /// they are there. Prior seconds do not move while a session runs —
  /// nothing is credited to the task until it stops — so reading them late
  /// gives the same answer as reading them at the start.
  SessionClock _withTask(SessionClock clock) {
    if (clock.taskName != null) return clock;
    final task = ref.read(selectedTaskProvider);
    if (task == null || task.id != clock.taskId) return clock;
    return clock.copyWith(
      taskName: task.name,
      taskSecondsBefore: task.totalSeconds,
    );
  }

  /// Push the clock's current answer into state, and keep the stored copy up
  /// to date.
  void _publish({bool persist = true}) {
    final clock = _clock;
    if (clock == null) {
      state = const TimerState();
      _written = null;
      return;
    }
    _clock = _withTask(clock);
    state = TimerState(
      status: _clock!.isPaused ? TimerStatus.paused : TimerStatus.running,
      sessionElapsed: _clock!.elapsedAt(_now()),
    );
    if (!persist) return;
    // The ticker publishes once a second and the clock does not change on a
    // tick — elapsed is derived from it, not written into it. Writing the
    // same bytes sixty times a minute would be a platform call a second for
    // nothing.
    final encoded = _clock!.encode();
    if (encoded == _written) return;
    _written = encoded;
    unawaited(_store.write(_clock!));
  }

  /// Stop and commit.
  ///
  /// [endedAt] corrects a session that ran past its work — the timer left
  /// on at lunch. Everything downstream, the milestone check included, uses
  /// the LOGGED amount, so a crossing the forgotten hours would have caused
  /// does not happen and one the real work caused still does.
  Future<StopOutcome> stop({DateTime? endedAt}) async {
    _ticker?.cancel();
    final clock = _clock;
    // The clock, not the last tick: a session stopped straight after the
    // phone was unlocked must count the time the screen was dark, and the
    // ticker has not run since it went off.
    final elapsed = clock == null
        ? state.sessionElapsed
        : (endedAt == null
              ? clock.elapsedAt(_now())
              : clock.loggedUntil(endedAt));
    final seconds = elapsed.inSeconds;
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
    _written = null;
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

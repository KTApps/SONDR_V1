import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';

/// Stopping a session that ran past its work.
///
/// The milestone check must read the LOGGED amount, never the raw elapsed:
/// a timer left on overnight would otherwise award a milestone for the
/// hours nobody worked.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 10, 18, 9);
  late DateTime now;
  late _MemoryStore store;
  late _FakeTasks tasks;

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        nowProvider.overrideWithValue(() => now),
        sessionStoreProvider.overrideWithValue(store),
        tasksRepositoryProvider.overrideWithValue(tasks),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    now = t0;
    store = _MemoryStore();
    tasks = _FakeTasks([const Task(id: 't1', name: 'Spanish')]);
  });

  group('the ask', () {
    test('fires at three hours of running, not before', () async {
      final c = container();
      final timer = c.read(timerControllerProvider.notifier);
      await timer.start();

      now = t0.add(const Duration(hours: 2, minutes: 59));
      expect(timer.shouldAskStillGoing, isFalse);
      now = t0.add(const Duration(hours: 3));
      expect(timer.shouldAskStillGoing, isTrue);
    });

    test('never fires for a paused session', () async {
      final c = container();
      final timer = c.read(timerControllerProvider.notifier);
      await timer.start();
      now = t0.add(const Duration(hours: 4));
      await timer.pause();
      now = t0.add(const Duration(hours: 20));
      expect(timer.shouldAskStillGoing, isFalse);
    });

    test('fires on a cold restore of a long-running session', () async {
      // A session started this morning; the app was killed and relaunched.
      store.saved = SessionClock(startedAt: t0, taskId: 't1');
      now = t0.add(const Duration(hours: 5));
      final c = container();
      final timer = c.read(timerControllerProvider.notifier);
      await timer.restore();
      expect(timer.shouldAskStillGoing, isTrue);
    });

    test('"Keep going" buys three more hours, and survives a relaunch', () async {
      final first = container();
      final timer = first.read(timerControllerProvider.notifier);
      await timer.start();
      now = t0.add(const Duration(hours: 3));
      expect(timer.shouldAskStillGoing, isTrue);

      await timer.confirmStillGoing();
      expect(timer.shouldAskStillGoing, isFalse);
      now = t0.add(const Duration(hours: 5, minutes: 59));
      expect(timer.shouldAskStillGoing, isFalse);
      now = t0.add(const Duration(hours: 6));
      expect(timer.shouldAskStillGoing, isTrue);

      // And the app being killed is not a way to be asked again early.
      first.dispose();
      now = t0.add(const Duration(hours: 4));
      final second = container();
      final restored = second.read(timerControllerProvider.notifier);
      await restored.restore();
      expect(restored.shouldAskStillGoing, isFalse);
    });
  });

  test('the debug backdate makes a session old enough to ask about', () async {
    final c = container();
    c.read(selectedTaskIdProvider.notifier).select('t1');
    final timer = c.read(timerControllerProvider.notifier);
    expect(timer.shouldAskStillGoing, isFalse);

    await timer.backdateForDebug(const Duration(hours: 4));
    expect(timer.shouldAskStillGoing, isTrue);
    expect(timer.clock!.taskId, 't1');
    expect(c.read(timerControllerProvider).isRunning, isTrue);
    expect(timer.clock!.elapsedAt(now), const Duration(hours: 4));
  });

  test('backdating a session already running rewinds it, keeping its pause',
      () async {
    final c = container();
    final timer = c.read(timerControllerProvider.notifier);
    await timer.start();
    now = t0.add(const Duration(minutes: 30));
    await timer.pause();
    now = t0.add(const Duration(minutes: 40));
    await timer.start();

    await timer.backdateForDebug(const Duration(hours: 4));
    // 40 minutes of clock plus four hours, less the ten-minute pause.
    expect(
      timer.clock!.elapsedAt(now),
      const Duration(hours: 4, minutes: 30),
    );
    expect(timer.clock!.pausedTotal, const Duration(minutes: 10));
  });

  group('stopping at a corrected end time', () {
    test('logs only up to that time, paused time included', () async {
      final c = container();
      c.read(selectedTaskIdProvider.notifier).select('t1');
      final timer = c.read(timerControllerProvider.notifier);
      await timer.start();
      // Worked 9–10, paused an hour, worked 11–12, then forgot until 18:00.
      now = t0.add(const Duration(hours: 1));
      await timer.pause();
      now = t0.add(const Duration(hours: 2));
      await timer.start();
      now = t0.add(const Duration(hours: 9));
      // The ticker has not run since the phone slept; resyncing is what
      // the app does on resume, and what makes the state honest.
      timer.resyncForTest();
      expect(c.read(timerControllerProvider).sessionElapsed,
          const Duration(hours: 8));

      final outcome = await timer.stop(
        endedAt: t0.add(const Duration(hours: 3)),
      );
      // One hour before the pause, one after.
      expect(outcome.loggedSeconds, 2 * 3600);
    });

    test('a milestone the real work earned is still celebrated', () async {
      tasks = _FakeTasks([
        Task(
          id: 't1',
          name: 'Spanish',
          secondsByDay: {'2026-10-17': 20 * 3600 - 1800},
        ),
      ]);
      final c = container();
      c.read(selectedTaskIdProvider.notifier).select('t1');
      await c.read(tasksProvider.future);
      final timer = c.read(timerControllerProvider.notifier);
      await timer.start();
      // Ran for nine hours; really worked one. Half an hour short of 20h, so
      // the corrected hour crosses it.
      now = t0.add(const Duration(hours: 9));
      final outcome = await timer.stop(
        endedAt: t0.add(const Duration(hours: 1)),
      );
      expect(outcome.loggedSeconds, 3600);
      expect(outcome.milestoneHours, 20);
    });

    test('a milestone only the forgotten hours would have earned does NOT '
        'fire', () async {
      // Five hours short of 20. One hour of real work does not get there;
      // the nine hours on the clock would have.
      tasks = _FakeTasks([
        Task(
          id: 't1',
          name: 'Spanish',
          secondsByDay: {'2026-10-17': 15 * 3600},
        ),
      ]);
      final c = container();
      c.read(selectedTaskIdProvider.notifier).select('t1');
      await c.read(tasksProvider.future);
      final timer = c.read(timerControllerProvider.notifier);
      await timer.start();
      now = t0.add(const Duration(hours: 9));

      final outcome = await timer.stop(
        endedAt: t0.add(const Duration(hours: 1)),
      );
      expect(outcome.loggedSeconds, 3600);
      expect(
        outcome.milestoneHours,
        isNull,
        reason: 'a milestone was awarded for hours nobody worked',
      );
    });

    test('stopping with no correction is the ordinary stop', () async {
      final c = container();
      c.read(selectedTaskIdProvider.notifier).select('t1');
      final timer = c.read(timerControllerProvider.notifier);
      await timer.start();
      now = t0.add(const Duration(hours: 4));
      final outcome = await timer.stop();
      expect(outcome.loggedSeconds, 4 * 3600);
      expect(store.saved, isNull);
    });
  });
}

class _MemoryStore implements SessionStore {
  SessionClock? saved;
  @override
  Future<SessionClock?> read() async => saved;
  @override
  Future<void> write(SessionClock clock) async => saved = clock;
  @override
  Future<void> clear() async => saved = null;
}

class _FakeTasks implements TasksRepository {
  @override
  Future<void> delete(String taskId) async {}

  _FakeTasks(this.tasks);
  final List<Task> tasks;
  @override
  Future<List<Task>> fetchAll() async => tasks;
  @override
  Future<Task> create(String name) async => throw UnimplementedError();
  @override
  Future<void> save(Task task) async {
    final i = tasks.indexWhere((t) => t.id == task.id);
    if (i >= 0) tasks[i] = task;
  }
}

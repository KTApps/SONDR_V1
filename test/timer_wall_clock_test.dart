import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';

/// The timer counts real time, not frames.
///
/// It used to be a one-second ticker incrementing a counter held only in
/// memory. A ticker stops the moment iOS suspends the app, so a locked phone
/// froze the session; and nothing was written down, so the app being
/// reclaimed mid-session lost it outright.
void main() {
  // The controller registers a lifecycle observer, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 10, 15, 9);

  late DateTime now;
  late _MemoryStore store;
  late _FakeTasks tasks;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        nowProvider.overrideWithValue(() => now),
        sessionStoreProvider.overrideWithValue(store),
        tasksRepositoryProvider.overrideWithValue(tasks),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    now = t0;
    store = _MemoryStore();
    tasks = _FakeTasks([const Task(id: 't1', name: 'Spanish')]);
  });

  test('time passes while the app is asleep', () {
    final c = makeContainer();
    c.read(timerControllerProvider.notifier).start();
    expect(c.read(timerControllerProvider).sessionElapsed, Duration.zero);

    // The phone locks. No ticks fire at all — that is the point.
    now = t0.add(const Duration(minutes: 47));
    // Reading on resume is what the lifecycle observer triggers.
    c.read(timerControllerProvider.notifier).resyncForTest();
    expect(
      c.read(timerControllerProvider).sessionElapsed,
      const Duration(minutes: 47),
      reason: 'the locked phone was treated as time that never happened',
    );
  });

  test('a paused gap is not counted, a running one is', () {
    final c = makeContainer();
    final timer = c.read(timerControllerProvider.notifier);
    timer.start();
    now = t0.add(const Duration(minutes: 10));
    timer.pause();

    // An hour asleep while paused.
    now = t0.add(const Duration(minutes: 70));
    timer.resyncForTest();
    expect(
      c.read(timerControllerProvider).sessionElapsed,
      const Duration(minutes: 10),
    );
    expect(c.read(timerControllerProvider).status, TimerStatus.paused);

    timer.start();
    now = t0.add(const Duration(minutes: 80));
    timer.resyncForTest();
    expect(
      c.read(timerControllerProvider).sessionElapsed,
      const Duration(minutes: 20),
    );
  });

  test('a session killed mid-run comes back on the next launch', () async {
    final first = makeContainer();
    first.read(selectedTaskIdProvider.notifier).select('t1');
    first.read(timerControllerProvider.notifier).start();
    expect(store.saved, isNotNull);

    // iOS reclaims the app. A whole new container, as a relaunch is.
    first.dispose();
    now = t0.add(const Duration(minutes: 25));

    final second = makeContainer();
    final restored = second.read(timerControllerProvider.notifier);
    await restored.restore();

    final state = second.read(timerControllerProvider);
    expect(state.isRunning, isTrue, reason: 'the session did not come back');
    expect(state.sessionElapsed, const Duration(minutes: 25));
    // And it knows what it is for: selection is not persisted, so without
    // this a restored session would credit nothing on Stop.
    expect(second.read(selectedTaskIdProvider), 't1');
  });

  test('a session paused before the kill comes back paused', () async {
    final first = makeContainer();
    final timer = first.read(timerControllerProvider.notifier);
    timer.start();
    now = t0.add(const Duration(minutes: 5));
    timer.pause();
    first.dispose();

    now = t0.add(const Duration(hours: 3));
    final second = makeContainer();
    await second.read(timerControllerProvider.notifier).restore();
    final state = second.read(timerControllerProvider);
    expect(state.status, TimerStatus.paused);
    expect(state.sessionElapsed, const Duration(minutes: 5));
  });

  test('stopping logs the wall clock, and clears the stored session',
      () async {
    final c = makeContainer();
    c.read(selectedTaskIdProvider.notifier).select('t1');
    c.read(timerControllerProvider.notifier).start();

    // Backgrounded for half an hour, stopped the moment it comes back —
    // before any tick could have run.
    now = t0.add(const Duration(minutes: 30));
    final outcome = await c.read(timerControllerProvider.notifier).stop();

    expect(outcome.loggedSeconds, 30 * 60);
    expect(store.saved, isNull, reason: 'the stopped session is still stored');
    expect(c.read(timerControllerProvider).status, TimerStatus.idle);
  });

  test('a milestone crossed while backgrounded still celebrates on stop',
      () async {
    // One minute short of 20 hours before this session starts.
    tasks = _FakeTasks([
      Task(
        id: 't1',
        name: 'Spanish',
        secondsByDay: {'2026-10-14': 20 * 3600 - 60},
      ),
    ]);
    final c = makeContainer();
    c.read(selectedTaskIdProvider.notifier).select('t1');
    await c.read(tasksProvider.future);
    c.read(timerControllerProvider.notifier).start();

    // The phone locks for ten minutes and crosses the band while asleep.
    now = t0.add(const Duration(minutes: 10));
    final outcome = await c.read(timerControllerProvider.notifier).stop();

    expect(outcome.loggedSeconds, 10 * 60);
    expect(
      outcome.milestoneHours,
      20,
      reason: 'the crossing happened in the dark and was missed',
    );
    expect(outcome.isFirstMilestone, isTrue);
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

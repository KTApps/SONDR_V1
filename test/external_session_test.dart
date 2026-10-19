import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/live_activity.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';

/// The session can change while the app is not looking.
///
/// Pause and Resume on the Lock Screen run in another process and write
/// straight to shared storage — the app may be suspended, or not running at
/// all. So the clock the app holds in memory is only ever a cache, and
/// anything that reads or writes the session has to re-read first. Writing
/// a stale copy back would undo a pause the owner made, and keep counting
/// time they had stopped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 10, 19, 9);

  late DateTime now;
  late _MemoryStore store;
  late _FakeTasks tasks;
  late _RecordingCard card;

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        nowProvider.overrideWithValue(() => now),
        sessionStoreProvider.overrideWithValue(store),
        tasksRepositoryProvider.overrideWithValue(tasks),
        liveActivityProvider.overrideWithValue(card),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  /// A session the app started and is counting.
  Future<TimerController> running() async {
    final timer = container().read(timerControllerProvider.notifier);
    await timer.restored;
    await timer.start();
    return timer;
  }

  /// What a Lock Screen tap does: writes the session, nothing else.
  void pausedFromTheLockScreen(DateTime at) {
    store.saved = store.saved!.pause(at);
  }

  void resumedFromTheLockScreen(DateTime at) {
    store.saved = store.saved!.resume(at);
  }

  setUp(() {
    now = t0;
    store = _MemoryStore();
    tasks = _FakeTasks([const Task(id: 't1', name: 'Spanish')]);
    card = _RecordingCard();
  });

  group('a pause made elsewhere', () {
    test('is picked up when the app comes back', () async {
      final timer = await running();
      now = t0.add(const Duration(minutes: 30));
      pausedFromTheLockScreen(now);
      now = t0.add(const Duration(hours: 2));

      await timer.sync();

      expect(timer.state.status, TimerStatus.paused);
      expect(
        timer.state.sessionElapsed,
        const Duration(minutes: 30),
        reason: 'the app kept counting through a pause it did not make',
      );
    });

    test('survives the app writing afterwards', () async {
      final timer = await running();
      now = t0.add(const Duration(minutes: 30));
      pausedFromTheLockScreen(now);
      now = t0.add(const Duration(hours: 2));

      // Anything the app does now must build on the pause, not bury it.
      await timer.confirmStillGoing();

      expect(store.saved!.isPaused, isTrue, reason: 'the pause was overwritten');
      expect(store.saved!.pausedAt, t0.add(const Duration(minutes: 30)));
    });

    test('is what gets logged when the app stops the session', () async {
      final c = container();
      c.read(selectedTaskIdProvider.notifier).select('t1');
      await c.read(tasksProvider.future);
      final timer = c.read(timerControllerProvider.notifier);
      await timer.restored;
      await timer.start();

      now = t0.add(const Duration(minutes: 30));
      pausedFromTheLockScreen(now);
      now = t0.add(const Duration(hours: 9));

      final outcome = await timer.stop();

      expect(
        outcome.loggedSeconds,
        30 * 60,
        reason: 'it logged the hours the session spent paused',
      );
    });

    test('stops the "Still going?" prompt', () async {
      final timer = await running();
      now = t0.add(const Duration(minutes: 30));
      pausedFromTheLockScreen(now);
      now = t0.add(const Duration(hours: 6));

      await timer.sync();

      expect(
        timer.shouldAskStillGoing,
        isFalse,
        reason: 'it asked about a session that has been stopped for hours',
      );
    });

    test('Start resumes it rather than beginning a second session', () async {
      final timer = await running();
      now = t0.add(const Duration(minutes: 30));
      pausedFromTheLockScreen(now);
      now = t0.add(const Duration(minutes: 50));

      await timer.start();

      expect(timer.state.status, TimerStatus.running);
      expect(timer.clock!.startedAt, t0, reason: 'the session restarted');
      expect(timer.clock!.pausedTotal, const Duration(minutes: 20));
      expect(timer.state.sessionElapsed, const Duration(minutes: 30));
    });
  });

  group('a resume made elsewhere', () {
    test('is picked up, and time runs again', () async {
      final timer = await running();
      now = t0.add(const Duration(minutes: 30));
      await timer.pause();
      now = t0.add(const Duration(minutes: 40));
      resumedFromTheLockScreen(now);
      now = t0.add(const Duration(minutes: 55));

      await timer.sync();

      expect(timer.state.status, TimerStatus.running);
      expect(timer.state.sessionElapsed, const Duration(minutes: 45));
    });

    test('follows the ordinary "Still going?" rules from then on', () async {
      final timer = await running();
      now = t0.add(const Duration(minutes: 30));
      await timer.pause();
      now = t0.add(const Duration(hours: 1));
      resumedFromTheLockScreen(now);

      now = t0.add(const Duration(hours: 3, minutes: 20));
      await timer.sync();
      expect(timer.shouldAskStillGoing, isFalse, reason: 'under three hours run');

      now = t0.add(const Duration(hours: 4));
      await timer.sync();
      expect(timer.shouldAskStillGoing, isTrue);
    });

    test('Pause pauses from where it actually is', () async {
      final timer = await running();
      now = t0.add(const Duration(minutes: 10));
      await timer.pause();
      now = t0.add(const Duration(minutes: 40));
      resumedFromTheLockScreen(now);
      now = t0.add(const Duration(minutes: 50));

      await timer.pause();

      expect(store.saved!.pausedAt, now);
      expect(store.saved!.pausedTotal, const Duration(minutes: 30));
      expect(timer.state.sessionElapsed, const Duration(minutes: 20));
    });
  });

  testWidgets('an external pause stops the ticker', (tester) async {
    // Nothing visible changes if the ticker keeps running over a paused
    // session — elapsed is frozen either way. What it leaves behind is a
    // timer firing once a second forever, and flutter_test fails a test
    // that ends with one pending. That is the assertion.
    final c = ProviderContainer(
      overrides: [
        nowProvider.overrideWithValue(() => now),
        sessionStoreProvider.overrideWithValue(store),
        tasksRepositoryProvider.overrideWithValue(tasks),
        liveActivityProvider.overrideWithValue(card),
      ],
    );
    final timer = c.read(timerControllerProvider.notifier);
    await timer.restored;
    await timer.start();
    now = t0.add(const Duration(minutes: 30));
    pausedFromTheLockScreen(now);

    await timer.sync();

    expect(timer.state.status, TimerStatus.paused);
    // Deliberately not disposed: disposing cancels the ticker and would
    // hide exactly what this is looking for.
  });

  group('the store is the truth, but an empty read is not', () {
    test('a session started a moment ago is not deleted by a stale read',
        () async {
      final timer = container().read(timerControllerProvider.notifier);
      await timer.restored;
      store.gate = _Gate();
      await timer.start();
      // The write has not landed; a sync in this window reads nothing.
      store.saved = null;

      await timer.sync();

      expect(
        timer.state.status,
        TimerStatus.running,
        reason: 'an empty read threw away a session that was just started',
      );
    });

    test('an unchanged store leaves the clock exactly as it was', () async {
      final timer = await running();
      final before = timer.clock;

      await timer.sync();

      expect(identical(timer.clock, before), isTrue);
    });

    test('a confirmation made elsewhere is kept', () async {
      final timer = await running();
      now = t0.add(const Duration(hours: 3));
      // Something else confirmed the session is real.
      store.saved = store.saved!.confirmedNow(now);

      await timer.sync();

      expect(timer.shouldAskStillGoing, isFalse);
      expect(timer.clock!.confirmedAt, const Duration(hours: 3));
    });
  });
}

class _Gate {}

class _RecordingCard implements LiveActivity {
  final List<String> calls = [];

  @override
  Stream<String> get links => const Stream<String>.empty();

  @override
  Future<void> show(SessionClock clock) async => calls.add('show');

  @override
  Future<void> clear() async => calls.add('clear');

  @override
  Future<void> ready() async => calls.add('ready');
}

class _MemoryStore implements SessionStore {
  SessionClock? saved;
  _Gate? gate;

  @override
  Future<SessionClock?> read() async => saved;

  @override
  Future<void> write(SessionClock clock) async {
    if (gate != null) {
      gate = null;
      return; // the write that has not landed yet
    }
    saved = clock;
  }

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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/live_activity.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';

/// A stop asked for on the Home Screen widget ends the session when it
/// was tapped, not when the app came to the front to hear about it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the card tap router', () {
    Future<List<String>> route(String action) async {
      final did = <String>[];
      await CardTapRouter(
        restored: Future.value(),
        alive: () => true,
        onHome: () => did.add('home'),
        onPause: () => did.add('pause'),
        onResume: () => did.add('resume'),
        onStop: () async => did.add('stop'),
        onStopAt: (at) async => did.add('stop@${at.millisecondsSinceEpoch}'),
      ).handle(action);
      return did;
    }

    test('a stop with an instant goes to onStopAt with it', () async {
      expect(await route('stop:1761380000000'), ['home', 'stop@1761380000000']);
    });

    test('a bare stop still goes to onStop', () async {
      expect(await route('stop'), ['home', 'stop']);
    });

    test('an unreadable instant is a bare stop, not a dropped one', () async {
      expect(await route('stop:soon'), ['home', 'stop']);
    });

    test('without onStopAt the instant is simply not used', () async {
      final did = <String>[];
      await CardTapRouter(
        restored: Future.value(),
        alive: () => true,
        onHome: () {},
        onPause: () {},
        onResume: () {},
        onStop: () async => did.add('stop'),
      ).handle('stop:1761380000000');
      expect(did, ['stop']);
    });
  });

  group('crediting up to the instant', () {
    final t0 = DateTime(2026, 10, 25, 9);
    late DateTime now;
    late _MemoryStore store;

    ProviderContainer makeContainer() {
      final container = ProviderContainer(
        overrides: [
          nowProvider.overrideWithValue(() => now),
          sessionStoreProvider.overrideWithValue(store),
          tasksRepositoryProvider.overrideWithValue(
            _FakeTasks([const Task(id: 't1', name: 'Spanish')]),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    setUp(() {
      now = t0;
      store = _MemoryStore();
    });

    test('the seconds after the tap are not credited', () async {
      final c = makeContainer();
      await c.read(tasksProvider.future);
      c.read(selectedTaskIdProvider.notifier).select('t1');
      final timer = c.read(timerControllerProvider.notifier);
      await timer.start();

      // Tapped Stop on the widget at +10:00; the app only heard at +10:04.
      final tapped = t0.add(const Duration(minutes: 10));
      now = tapped.add(const Duration(seconds: 4));
      final outcome = await timer.stop(endedAt: tapped);

      expect(outcome.loggedSeconds, 10 * 60);
      expect(
        c.read(tasksProvider).value!.single.totalSeconds,
        10 * 60,
        reason: 'the seconds between the tap and the app waking were credited',
      );
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
  _FakeTasks(this.tasks);

  final List<Task> tasks;

  @override
  Future<List<Task>> fetchAll() async => tasks;

  @override
  Future<Task> create(String name) async => throw UnimplementedError();

  @override
  Future<void> delete(String taskId) async {}

  @override
  Future<void> save(Task task) async {
    final i = tasks.indexWhere((t) => t.id == task.id);
    if (i >= 0) tasks[i] = task;
  }
}

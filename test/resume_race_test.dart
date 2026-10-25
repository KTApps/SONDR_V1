import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';

/// The app must not race itself over the stored session.
///
/// Setting the timer's state notifies listeners synchronously, and Home's
/// "Still going?" check reads the store the moment a session starts
/// running. On the device that read went out BEFORE the resume had been
/// written, came back with the old paused session, and `sync()` adopted
/// it: the stored clock ran on while the screen stood still on
/// "Stop | Start" — until a second tap read the truth back.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 10, 25, 9);
  late DateTime now;
  late _SlowStore store;

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
    store = _SlowStore();
  });

  test('a read fired on the running transition sees the resume', () async {
    final c = makeContainer();
    final timer = c.read(timerControllerProvider.notifier);
    // What Home does: on not-running → running, read the store at once.
    c.listen(timerControllerProvider, (previous, next) {
      if (previous?.isRunning != true && next.isRunning) {
        unawaited(timer.sync());
      }
    });

    await timer.start();
    now = t0.add(const Duration(minutes: 2));
    await timer.pause();
    await store.settled;

    now = t0.add(const Duration(minutes: 2, seconds: 10));
    await timer.start();
    await store.settled;
    await pumpEventQueue();

    expect(
      c.read(timerControllerProvider).status,
      TimerStatus.running,
      reason: 'the screen went back to paused while the store ran on',
    );
    expect(timer.isTicking, isTrue, reason: 'the clock is not repainting');
    expect(store.saved?.isPaused, isFalse, reason: 'the store is paused');
  });
}

/// A store whose writes land a turn later, as a platform channel's do,
/// and which counts its reads.
class _SlowStore implements SessionStore {
  SessionClock? saved;
  int reads = 0;
  Future<void> settled = Future.value();

  @override
  Future<SessionClock?> read() async {
    reads++;
    return saved;
  }

  @override
  Future<void> write(SessionClock clock) {
    final landing = Future<void>.delayed(Duration.zero, () => saved = clock);
    settled = landing;
    return landing;
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
  Future<void> delete(String taskId) async {}

  @override
  Future<void> save(Task task) async {
    final i = tasks.indexWhere((t) => t.id == task.id);
    if (i >= 0) tasks[i] = task;
  }
}

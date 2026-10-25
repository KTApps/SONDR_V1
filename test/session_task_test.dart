import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';

/// The stored session's taskId is the only truth for which task a
/// session belongs to.
///
/// A session can be started from the Home Screen widget for a task Home
/// has not selected. Crediting the selection gave the widget's minutes
/// — and its milestone — to the wrong task. Every surface credits and
/// names the task the session itself says it is for.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 10, 25, 9);
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
    tasks = _FakeTasks([
      const Task(id: 'a', name: 'Yah'),
      const Task(id: 'b', name: 'Test 69'),
    ]);
  });

  int total(ProviderContainer c, String id) => c
      .read(tasksProvider)
      .value!
      .firstWhere((t) => t.id == id)
      .totalSeconds;

  /// What the widget does: writes a session for B into shared storage
  /// while the app, with A selected, is not looking.
  Future<void> widgetStarts(ProviderContainer c, String taskId) async {
    await c.read(tasksProvider.future);
    c.read(selectedTaskIdProvider.notifier).select('a');
    store.saved = SessionClock(
      startedAt: now,
      taskId: taskId,
      taskName: taskId == 'b' ? 'Test 69' : 'Yah',
    );
    await c.read(timerControllerProvider.notifier).sync();
  }

  test('a session started for B while A is selected credits B', () async {
    final c = makeContainer();
    await widgetStarts(c, 'b');
    // And even if Home's eye wanders back to A while B runs, the session
    // is still B's: the credit follows the session, not the selection.
    c.read(selectedTaskIdProvider.notifier).select('a');

    now = t0.add(const Duration(minutes: 10));
    final outcome = await c.read(timerControllerProvider.notifier).stop();

    expect(outcome.taskId, 'b');
    expect(outcome.taskName, 'Test 69');
    expect(total(c, 'b'), 10 * 60);
    expect(total(c, 'a'), 0, reason: 'the selected task was credited');
  });

  test('the same session, ended by signing out, still credits B', () async {
    final c = makeContainer();
    await widgetStarts(c, 'b');
    c.read(selectedTaskIdProvider.notifier).select('a');

    // Sign-out commits without discarding first, then discards.
    now = t0.add(const Duration(minutes: 10));
    final timer = c.read(timerControllerProvider.notifier);
    final outcome = await timer.commitKeepingSession();
    await timer.discard();

    expect(outcome.taskId, 'b');
    expect(total(c, 'b'), 10 * 60);
    expect(total(c, 'a'), 0);
  });

  test('sync() selects the task that is running', () async {
    final c = makeContainer();
    await widgetStarts(c, 'b');
    expect(
      c.read(selectedTaskIdProvider),
      'b',
      reason: 'Home kept showing the task that is not running',
    );
  });

  test('a clock with no task still falls back to the selection', () async {
    final c = makeContainer();
    await c.read(tasksProvider.future);
    c.read(selectedTaskIdProvider.notifier).select('a');
    store.saved = SessionClock(startedAt: now);
    await c.read(timerControllerProvider.notifier).sync();

    now = t0.add(const Duration(minutes: 5));
    final outcome = await c.read(timerControllerProvider.notifier).stop();
    expect(outcome.taskId, 'a');
    expect(total(c, 'a'), 5 * 60);
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

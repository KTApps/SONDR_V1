import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/live_activity.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';

/// A session is credited once, however many times it is stopped.
///
/// Crediting is a read-modify-write: read the day's total, add the
/// session, write the sum back. Offline, Firestore queues the write and
/// applies it to its own cache straight away, so the write "fails" (no
/// server acknowledgement) while the local copy already has the time. If
/// the app re-reads the list before the owner tries again — a relaunch is
/// enough — the retry reads the credited total and adds the session on
/// top of itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 10, 20, 9);

  late DateTime now;
  late _MemoryStore store;
  late _QueueingTasks tasks;
  late _SilentCard card;

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

  Future<TimerController> sessionOn(ProviderContainer c) async {
    c.read(selectedTaskIdProvider.notifier).select('t1');
    await c.read(tasksProvider.future);
    final timer = c.read(timerControllerProvider.notifier);
    await timer.restored;
    await timer.start();
    return timer;
  }

  int totalOf() => tasks.tasks.single.totalSeconds;

  setUp(() {
    now = t0;
    store = _MemoryStore();
    card = _SilentCard();
    tasks = _QueueingTasks([const Task(id: 't1', name: 'Spanish')]);
  });

  test('a credit that was queued but not confirmed is not added twice',
      () async {
    final c = container();
    final timer = await sessionOn(c);
    now = t0.add(const Duration(hours: 2));

    // Offline: the write reaches the local cache and never gets an
    // acknowledgement. The session is kept, as the sign-out guard does.
    tasks.queueWithoutConfirming = true;
    await expectLater(timer.commitKeepingSession(), throwsA(isA<Object>()));
    expect(totalOf(), 2 * 3600, reason: 'the cache did not take the write');
    expect(timer.clock, isNotNull, reason: 'the session was thrown away');

    // The app re-reads the list — a relaunch, or anything that invalidates
    // it — and sees the credited total.
    c.invalidate(tasksProvider);
    await c.read(tasksProvider.future);

    // Back online, the owner tries again.
    tasks.queueWithoutConfirming = false;
    await timer.commitKeepingSession();

    expect(
      totalOf(),
      2 * 3600,
      reason: 'the same session was credited twice',
    );
  });

  test('the retry still reaches the server, so the caller can let go',
      () async {
    final c = container();
    final timer = await sessionOn(c);
    now = t0.add(const Duration(hours: 1));
    tasks.queueWithoutConfirming = true;
    await expectLater(timer.commitKeepingSession(), throwsA(isA<Object>()));
    c.invalidate(tasksProvider);
    await c.read(tasksProvider.future);
    tasks.saves = 0;

    tasks.queueWithoutConfirming = false;
    await timer.commitKeepingSession();

    expect(
      tasks.saves,
      1,
      reason: 'the retry wrote nothing, so nothing was ever confirmed',
    );
  });

  test('a retry after midnight does not open a second day', () async {
    final c = container();
    final timer = await sessionOn(c);
    now = t0.add(const Duration(hours: 2));
    tasks.queueWithoutConfirming = true;
    await expectLater(timer.commitKeepingSession(), throwsA(isA<Object>()));
    c.invalidate(tasksProvider);
    await c.read(tasksProvider.future);

    // The retry happens the next morning.
    now = t0.add(const Duration(days: 1));
    tasks.queueWithoutConfirming = false;
    await timer.commitKeepingSession();

    expect(totalOf(), 2 * 3600);
    expect(
      tasks.tasks.single.secondsByDay.keys.where((d) => d == DayKey.of(now)),
      isEmpty,
      reason: 'it logged the session again under the next day',
    );
  });

  test('an ordinary stop still credits, once', () async {
    final c = container();
    final timer = await sessionOn(c);
    now = t0.add(const Duration(hours: 3));

    final outcome = await timer.stop();

    expect(outcome.loggedSeconds, 3 * 3600);
    expect(totalOf(), 3 * 3600);
  });

  test('two different sessions are both counted', () async {
    final c = container();
    final timer = await sessionOn(c);
    now = t0.add(const Duration(hours: 1));
    await timer.stop();

    now = t0.add(const Duration(hours: 2));
    await timer.start();
    now = t0.add(const Duration(hours: 3));
    await timer.stop();

    expect(totalOf(), 2 * 3600, reason: 'the second session was swallowed');
  });

  group('the document', () {
    final day = DateTime(2026, 10, 20, 9);

    test('one written before the field existed still credits', () {
      // No creditedSessions key at all — the shape every task has today.
      final old = Task.fromMap('t1', {
        'name': 'Spanish',
        'secondsByDay': {'2026-10-19': 3600},
      });

      expect(old.creditedSessions, isEmpty);
      final credited = old.crediting(Task.sessionKey(day), 1800, day);
      expect(credited.totalSeconds, 5400);
      expect(credited.creditedSessions, [Task.sessionKey(day)]);
    });

    test('the key survives the round trip', () {
      final credited = const Task(id: 't1', name: 'Spanish')
          .crediting(Task.sessionKey(day), 1800, day);

      final back = Task.fromMap('t1', credited.toMap());

      expect(back.creditedSessions, [Task.sessionKey(day)]);
      expect(back.hasCredited(Task.sessionKey(day)), isTrue);
    });

    test('it remembers a bounded number of sessions, newest kept', () {
      var task = const Task(id: 't1', name: 'Spanish');
      for (var i = 0; i < 40; i++) {
        task = task.crediting(
          Task.sessionKey(day.add(Duration(minutes: i))),
          60,
          day,
        );
      }

      expect(task.totalSeconds, 40 * 60, reason: 'a credit went missing');
      expect(task.creditedSessions.length, lessThanOrEqualTo(20));
      expect(
        task.hasCredited(Task.sessionKey(day.add(const Duration(minutes: 39)))),
        isTrue,
        reason: 'the most recent session is the one a retry would be for',
      );
    });

    test('archiving and unkeyed logging carry the keys through', () {
      final credited = const Task(id: 't1', name: 'Spanish')
          .crediting(Task.sessionKey(day), 1800, day);

      expect(credited.archivedAs(true).creditedSessions, isNotEmpty);
      expect(credited.addingSeconds(60, day).creditedSessions, isNotEmpty);
    });
  });

  test('a session stopped twice over is credited once', () async {
    // Not reachable through the UI, but the guard should not depend on
    // that: the same session id must never be added twice.
    final c = container();
    final timer = await sessionOn(c);
    now = t0.add(const Duration(hours: 2));

    await timer.commitKeepingSession();
    c.invalidate(tasksProvider);
    await c.read(tasksProvider.future);
    await timer.commitKeepingSession();

    expect(totalOf(), 2 * 3600);
  });
}

class _SilentCard implements LiveActivity {
  @override
  Stream<void> get sessionChanges => const Stream<void>.empty();
  @override
  Stream<String> get links => const Stream<String>.empty();
  @override
  Future<void> show(SessionClock clock) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<void> ready() async {}
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

/// A repository that behaves the way Firestore does offline: the write
/// lands in the local copy immediately, and then never gets an
/// acknowledgement.
///
/// It keeps DOCUMENTS, not Tasks, and merges a save into the one already
/// there — so anything a Task fails to write down is as lost here as it
/// would be on the server. (The merge is shallow, where Firestore's
/// descends into nested maps; every write here carries the whole map, so
/// the difference does not arise.)
class _QueueingTasks implements TasksRepository {
  @override
  Future<void> delete(String taskId) async {}

  _QueueingTasks(List<Task> seed) {
    for (final t in seed) {
      docs[t.id] = t.toMap();
    }
  }

  final Map<String, Map<String, dynamic>> docs = {};
  bool queueWithoutConfirming = false;
  int saves = 0;

  List<Task> get tasks => [
        for (final e in docs.entries) Task.fromMap(e.key, e.value),
      ];

  @override
  Future<List<Task>> fetchAll() async => tasks;

  @override
  Future<Task> create(String name) async => throw UnimplementedError();

  @override
  Future<void> save(Task task) async {
    saves++;
    docs[task.id] = {...?docs[task.id], ...task.toMap()};
    if (queueWithoutConfirming) {
      throw StateError('queued, not acknowledged');
    }
  }
}

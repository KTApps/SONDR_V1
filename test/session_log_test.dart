import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/session_log.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';

/// Every credit leaves a session in the log — once.
void main() {
  late _Log log;
  late _FakeTasks tasks;

  ProviderContainer makeContainer() {
    final c = ProviderContainer(
      overrides: [
        tasksRepositoryProvider.overrideWithValue(tasks),
        sessionLogProvider.overrideWithValue(log),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    log = _Log();
    tasks = _FakeTasks([const Task(id: 't1', name: 'Spanish')]);
  });

  test('a credit records the session: when it began, how long', () async {
    final c = makeContainer();
    await c.read(tasksProvider.future);
    await c.read(tasksProvider.notifier).logSeconds(
      't1', 1500, DateTime(2026, 10, 2, 9), session: '1761000000000',
    );
    expect(log.records, [
      const SessionRecord(taskId: 't1', at: 1761000000000, seconds: 1500),
    ]);
  });

  test('the same session credited twice is logged once', () async {
    final c = makeContainer();
    await c.read(tasksProvider.future);
    final n = c.read(tasksProvider.notifier);
    await n.logSeconds('t1', 1500, DateTime(2026, 10, 2, 9), session: 'k1');
    await n.logSeconds('t1', 1500, DateTime(2026, 10, 2, 9), session: 'k1');
    expect(log.records.length, 1);
    // And the task was credited once, as before.
    expect(c.read(tasksProvider).value!.single.totalSeconds, 1500);
  });

  test('two sessions are two records, in order', () async {
    final c = makeContainer();
    await c.read(tasksProvider.future);
    final n = c.read(tasksProvider.notifier);
    await n.logSeconds('t1', 600, DateTime(2026, 10, 2), session: '1000');
    await n.logSeconds('t1', 900, DateTime(2026, 10, 3), session: '2000');
    expect(log.records.map((r) => r.at), [1000, 2000]);
    expect(log.records.map((r) => r.seconds), [600, 900]);
  });

  test('a credit with no session key is keyed by its moment', () async {
    final c = makeContainer();
    await c.read(tasksProvider.future);
    final when = DateTime(2026, 10, 2, 9);
    await c.read(tasksProvider.notifier).logSeconds('t1', 60, when);
    expect(log.records.single.at, when.millisecondsSinceEpoch);
  });

  test('the record names one document per session', () {
    const r = SessionRecord(taskId: 't1', at: 5, seconds: 1);
    expect(r.id, 't1_5');
    expect(SessionRecord.fromMap(r.toMap()), r);
    expect(SessionRecord.fromMap({'taskId': 't1', 'at': 'soon', 'seconds': 1}), isNull);
  });
}

class _Log implements SessionLog {
  final List<SessionRecord> records = [];

  @override
  Future<void> record(SessionRecord session) async => records.add(session);

  @override
  Future<List<SessionRecord>> forTask(String taskId) async =>
      [for (final r in records) if (r.taskId == taskId) r];
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

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/habits/models/daily_habits.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/widget/widget_bridge.dart';
import 'package:sondr/features/widget/widget_publisher.dart';
import 'package:sondr/features/widget/widget_selection.dart';
import 'package:sondr/features/widget/widget_snapshot.dart';

/// What the Home Screen widget is told, and when.
///
/// The widget is a separate process that may draw days after the app last
/// ran, so it reads numbers rather than a model: this is the shape of
/// those numbers, and the moments the app writes them.
final now = DateTime(2026, 10, 24, 9);

Task _task(
  String name, {
  Map<String, int> days = const {},
  int total = 0,
  bool archived = false,
}) => Task(
  id: name,
  name: name,
  secondsByDay: {
    ...days,
    if (total > 0) '2020-01-01': total - days.values.fold(0, (a, b) => a + b),
  },
  archived: archived,
);

class _Recording implements WidgetBridge {
  final List<WidgetSnapshot> published = [];

  @override
  Future<void> publish(WidgetSnapshot snapshot) async =>
      published.add(snapshot);
}

/// The real store is a platform channel with nothing behind it in a
/// test, and the publisher watches the timer — which reads it.
class _NoStore implements SessionStore {
  @override
  Future<SessionClock?> read() async => null;

  @override
  Future<void> write(SessionClock clock) async {}

  @override
  Future<void> clear() async {}
}

class _Tasks implements TasksRepository {
  _Tasks(this.tasks);

  List<Task> tasks;

  @override
  Future<List<Task>> fetchAll() async => tasks;

  @override
  Future<void> save(Task task) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Task> create(String name) async => throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the document', () {
    test('carries every live task, in the app\'s order', () {
      final snap = WidgetSnapshot.of(
        tasks: [
          _task('Golf', days: {'2026-10-24': 3600}, total: 72000),
          _task('Run', days: {'2026-10-23': 1800}, total: 1800),
          _task('Gone', archived: true),
        ],
        habits: null,
        selectedTaskId: 'Golf',
        now: now,
      );
      expect([for (final t in snap.tasks) t.name], ['Golf', 'Run']);
      expect(snap.segments, [3600, 0]);
      expect(snap.selectedTaskId, 'Golf');
    });

    test('a task carries what a widget draws, and nothing else', () {
      final snap = WidgetSnapshot.of(
        tasks: [_task('Golf', days: {'2026-10-24': 3600}, total: 72000)],
        habits: null,
        selectedTaskId: null,
        now: now,
      );
      final golf = snap.tasks.single;
      expect(golf.id, 'Golf');
      expect(golf.today, 3600);
      expect(golf.total, 72000);
      // 72000s is 20h exactly: one milestone reached, and the next ring
      // starts empty — the same rule every ring in the app follows.
      expect(golf.progress, 0);
      expect(golf.lastTracked, '2026-10-24');
      expect(golf.toMap().keys.toSet(),
          {'id', 'name', 'today', 'total', 'progress', 'last'});
    });

    test('the dial and the habits come with it', () {
      final snap = WidgetSnapshot.of(
        tasks: [
          _task('Golf', days: {'2026-10-24': 3600}),
          _task('Run', days: {'2026-10-24': 600}),
        ],
        habits: const DailyHabits(dayKey: '2026-10-24', ticks: [
          HabitTick(habitId: 'a', name: 'Read', done: true),
          HabitTick(habitId: 'b', name: 'Walk', done: false),
        ]),
        selectedTaskId: '',
        now: now,
      );
      expect(snap.segments, [3600, 600]);
      expect(snap.habitsDone, 1);
      expect(snap.habitsTotal, 2);
    });

    test('the running session is NOT in it', () {
      final snap = WidgetSnapshot.of(
        tasks: const [],
        habits: null,
        selectedTaskId: null,
        now: now,
      );
      // One clock, in one place: the widget reads sondr.session, which is
      // the same document the Live Activity and the app read.
      expect(
        (jsonDecode(snap.toJson()) as Map).keys.toSet(),
        {'v', 'tasks', 'segments', 'habitsDone', 'habitsTotal', 'selected'},
      );
    });

    test('and it says which shape it is', () {
      expect(WidgetSnapshot.version, 1);
      expect(WidgetSnapshot.key, 'sondr.widget');
      final decoded = jsonDecode(
        WidgetSnapshot.of(
          tasks: const [],
          habits: null,
          selectedTaskId: null,
          now: now,
        ).toJson(),
      ) as Map;
      expect(decoded['v'], 1);
    });

    test('two that would draw the same are the same', () {
      WidgetSnapshot make(int seconds) => WidgetSnapshot.of(
        tasks: [_task('Golf', days: {'2026-10-24': seconds})],
        habits: null,
        selectedTaskId: null,
        now: now,
      );
      expect(make(60), make(60));
      expect(make(60), isNot(make(61)));
    });
  });

  group('when it is written', () {
    late _Recording bridge;
    late _Tasks repo;

    /// Boots the publisher and waits for the first load, so what follows
    /// is measured against a settled widget rather than a loading one.
    Future<ProviderContainer> boot() async {
      bridge = _Recording();
      repo = _Tasks([_task('Golf', days: {'2026-10-24': 60})]);
      final c = ProviderContainer(
        overrides: [
          widgetBridgeProvider.overrideWithValue(bridge),
          tasksRepositoryProvider.overrideWithValue(repo),
          nowProvider.overrideWithValue(() => now),
          sessionStoreProvider.overrideWithValue(_NoStore()),
        ],
      );
      addTearDown(c.dispose);
      c.listen(widgetPublisherProvider, (_, _) {});
      await c.read(tasksProvider.future);
      await Future<void>.delayed(Duration.zero);
      return c;
    }

    test('at once, before anything has loaded', () async {
      bridge = _Recording();
      repo = _Tasks([_task('Golf', days: {'2026-10-24': 60})]);
      final c = ProviderContainer(
        overrides: [
          widgetBridgeProvider.overrideWithValue(bridge),
          tasksRepositoryProvider.overrideWithValue(repo),
          nowProvider.overrideWithValue(() => now),
          sessionStoreProvider.overrideWithValue(_NoStore()),
        ],
      );
      addTearDown(c.dispose);
      c.listen(widgetPublisherProvider, (_, _) {});
      // A widget added while the app was shut has something to draw the
      // moment the app opens, rather than after its first fetch.
      expect(bridge.published, hasLength(1));
      expect(bridge.published.single.tasks, isEmpty);

      // And then the real thing, once it arrives.
      await c.read(tasksProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.published.last.tasks, hasLength(1));
    });

    test('when the selection changes', () async {
      final c = await boot();
      final before = bridge.published.length;
      c.read(selectedTaskIdProvider.notifier).select('Golf');
      await Future<void>.delayed(Duration.zero);
      expect(bridge.published.length, before + 1);
      expect(bridge.published.last.selectedTaskId, 'Golf');
    });

    test('when the tasks change', () async {
      final c = await boot();
      final before = bridge.published.length;
      repo.tasks = [
        _task('Golf', days: {'2026-10-24': 60}),
        _task('Run', days: {'2026-10-24': 30}),
      ];
      c.invalidate(tasksProvider);
      await c.read(tasksProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(bridge.published.length, greaterThan(before));
      expect(bridge.published.last.tasks, hasLength(2));
    });

    test('and not when nothing it draws has changed', () async {
      final c = await boot();
      final before = bridge.published.length;
      c.invalidate(tasksProvider);
      await c.read(tasksProvider.future);
      await Future<void>.delayed(Duration.zero);
      expect(
        bridge.published.length,
        before,
        reason: 'a refetch of the same tasks redrew the widget',
      );
    });
  });

  group('a selection the widget made while the app was shut', () {
    test('is taken once, and applied', () async {
      final inbox = _Inbox('Golf');
      final c = ProviderContainer(
        overrides: [
          widgetSelectionInboxProvider.overrideWithValue(inbox),
          tasksRepositoryProvider.overrideWithValue(
            _Tasks([_task('Golf'), _task('Run')]),
          ),
        ],
      );
      addTearDown(c.dispose);

      await c.read(applyWidgetSelectionProvider)();
      expect(c.read(selectedTaskIdProvider), 'Golf');
      expect(inbox.taken, 1);

      // Taken once: a second launch does not override what the person
      // has chosen since.
      c.read(selectedTaskIdProvider.notifier).select('Run');
      await c.read(applyWidgetSelectionProvider)();
      expect(c.read(selectedTaskIdProvider), 'Run');
    });

    test('a task deleted since is ignored', () async {
      final c = ProviderContainer(
        overrides: [
          widgetSelectionInboxProvider.overrideWithValue(_Inbox('Gone')),
          tasksRepositoryProvider.overrideWithValue(_Tasks([_task('Golf')])),
        ],
      );
      addTearDown(c.dispose);
      await c.read(applyWidgetSelectionProvider)();
      expect(c.read(selectedTaskIdProvider), isNull);
    });

    test('nothing left is nothing done', () async {
      final c = ProviderContainer(
        overrides: [
          widgetSelectionInboxProvider.overrideWithValue(_Inbox(null)),
          tasksRepositoryProvider.overrideWithValue(_Tasks([_task('Golf')])),
        ],
      );
      addTearDown(c.dispose);
      await c.read(applyWidgetSelectionProvider)();
      expect(c.read(selectedTaskIdProvider), isNull);
    });
  });
}

/// What the widget left behind.
class _Inbox implements WidgetSelectionInbox {
  _Inbox(this._id);

  String? _id;
  int taken = 0;

  @override
  Future<String?> take() async {
    taken++;
    final id = _id;
    _id = null;
    return id;
  }
}

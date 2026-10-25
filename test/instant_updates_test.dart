import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/live_activity.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';
import 'package:sondr/features/widget/widget_bridge.dart';
import 'package:sondr/features/widget/widget_publisher.dart';
import 'package:sondr/features/widget/widget_snapshot.dart';

/// Three surfaces, one session.
///
/// Pausing on the Lock Screen card, starting on the Home Screen widget
/// and tapping Start in the app all change the same stored session — in
/// three different processes. Each one has to tell the other two at
/// once, or the app counts on past a pause and the widget draws a clock
/// that stopped ten minutes ago.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 10, 25, 9);
  late DateTime now;
  late _MemoryStore store;
  late _Card card;
  late _Bridge bridge;

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        nowProvider.overrideWithValue(() => now),
        sessionStoreProvider.overrideWithValue(store),
        liveActivityProvider.overrideWithValue(card),
        widgetBridgeProvider.overrideWithValue(bridge),
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
    card = _Card();
    bridge = _Bridge();
  });

  tearDown(() => card.dispose());

  group('a change from outside the app', () {
    test('a pause on the card reaches the running app at once', () async {
      final c = makeContainer();
      final timer = c.read(timerControllerProvider.notifier);
      await timer.start();
      expect(c.read(timerControllerProvider).status, TimerStatus.running);

      // What the Lock Screen's Pause does: writes the session in another
      // process, then posts. Nothing is sent down the channel but the
      // fact that something happened.
      now = t0.add(const Duration(minutes: 10));
      store.saved = store.saved!.pause(now);
      card.sessionChanged();
      await pumpEventQueue();

      expect(
        c.read(timerControllerProvider).status,
        TimerStatus.paused,
        reason: 'the app kept counting through a pause it was told about',
      );
      expect(
        c.read(timerControllerProvider).sessionElapsed,
        const Duration(minutes: 10),
      );
    });

    test('with no word from Swift the app never finds out', () async {
      // The falsification, kept: this is the whole value of the
      // notification, and without it the app is wrong until it is next
      // brought to the foreground.
      final c = makeContainer();
      final timer = c.read(timerControllerProvider.notifier);
      await timer.start();

      now = t0.add(const Duration(minutes: 10));
      store.saved = store.saved!.pause(now);
      await pumpEventQueue();

      expect(c.read(timerControllerProvider).status, TimerStatus.running);
    });
  });

  group('the widget is redrawn', () {
    test('on every change of the session, not of the document', () async {
      final c = makeContainer();
      // The publisher is listened to at launch by the boot gate.
      c.listen(widgetPublisherProvider, (_, _) {});
      await c.read(tasksProvider.future);
      final before = bridge.reloads;

      final timer = c.read(timerControllerProvider.notifier);
      await timer.start();
      await timer.pause();
      await timer.start();
      await timer.stop();

      expect(
        bridge.reloads - before,
        4,
        reason: 'start, pause, going again and stopping are four redraws',
      );
    });
  });
}

/// A card that can be told something happened to the session.
class _Card implements LiveActivity {
  final StreamController<void> _changes = StreamController<void>.broadcast();

  void sessionChanged() => _changes.add(null);
  void dispose() => _changes.close();

  @override
  Stream<void> get sessionChanges => _changes.stream;

  @override
  Stream<String> get links => const Stream<String>.empty();

  @override
  Future<void> show(SessionClock clock) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> ready() async {}
}

class _Bridge implements WidgetBridge {
  int reloads = 0;
  final List<WidgetSnapshot> published = [];

  @override
  Future<void> publish(WidgetSnapshot snapshot) async =>
      published.add(snapshot);

  @override
  Future<void> reload() async => reloads++;
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

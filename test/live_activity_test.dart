import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/live_activity.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';

/// The Lock Screen card, and the two ways it can lie.
///
/// It can say a session is running when it is over — a card left behind by a
/// stop, a sign-out, or a launch that was killed — or it can be tapped before
/// the app has read the session it claims to be about, and stop nothing.
void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 10, 18, 9);

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

  setUp(() {
    now = t0;
    store = _MemoryStore();
    tasks = _FakeTasks([const Task(id: 't1', name: 'Spanish')]);
    card = _RecordingCard();
  });

  group('the card follows the session', () {
    test('starting a session puts one up', () async {
      final timer = container().read(timerControllerProvider.notifier);
      await timer.restored;
      card.calls.clear();

      await timer.start();

      expect(card.calls, ['show']);
      expect(card.shown.single.startedAt, t0);
    });

    test('pausing says so', () async {
      final timer = container().read(timerControllerProvider.notifier);
      await timer.restored;
      card.calls.clear();
      await timer.start();
      now = t0.add(const Duration(minutes: 30));

      await timer.pause();

      expect(card.calls, ['show', 'show']);
      expect(card.shown.last.isPaused, isTrue);
      expect(card.shown.last.pausedAt, now);
    });

    test('resuming says so', () async {
      final timer = container().read(timerControllerProvider.notifier);
      await timer.restored;
      card.calls.clear();
      await timer.start();
      now = t0.add(const Duration(minutes: 30));
      await timer.pause();
      now = t0.add(const Duration(minutes: 40));

      await timer.start();

      expect(card.calls, ['show', 'show', 'show']);
      expect(card.shown.last.isPaused, isFalse);
      expect(card.shown.last.pausedTotal, const Duration(minutes: 10));
    });

    test('the card carries the task name and its hours so far', () async {
      tasks = _FakeTasks([
        Task(id: 't1', name: 'Spanish', secondsByDay: const {'2026-10-17': 7200}),
      ]);
      final c = container();
      c.read(selectedTaskIdProvider.notifier).select('t1');
      // The name comes off the loaded list, not the id.
      await c.read(tasksProvider.future);
      expect(c.read(selectedTaskProvider)?.name, 'Spanish');

      await c.read(timerControllerProvider.notifier).start();

      expect(card.shown.single.taskName, 'Spanish');
      expect(card.shown.single.taskSecondsBefore, 7200);
    });
  });

  group('every way out takes the card down', () {
    Future<void> stopAfter(
      Duration ran,
      Future<void> Function(TimerController) how,
    ) async {
      final c = container();
      c.read(selectedTaskIdProvider.notifier).select('t1');
      final timer = c.read(timerControllerProvider.notifier);
      // Let the launch's own tidy-up land first, so what is counted below is
      // the stop and nothing else.
      await timer.restored;
      card.calls.clear();
      await timer.start();
      now = t0.add(ran);
      card.calls.clear();
      await how(timer);
    }

    test('Stop', () async {
      await stopAfter(const Duration(hours: 1), (t) => t.stop());
      expect(card.calls, ['clear']);
    });

    test('Set end time', () async {
      await stopAfter(
        const Duration(hours: 9),
        (t) => t.stop(endedAt: t0.add(const Duration(hours: 2))),
      );
      expect(card.calls, ['clear']);
    });

    test('a session too short to photograph', () async {
      await stopAfter(const Duration(seconds: 12), (t) => t.stop());
      expect(
        card.calls,
        ['clear'],
        reason: 'under a minute skips the camera, not the card',
      );
    });

    test('a session with no task at all', () async {
      final timer = container().read(timerControllerProvider.notifier);
      await timer.restored;
      card.calls.clear();
      await timer.start();
      now = t0.add(const Duration(hours: 1));
      card.calls.clear();

      await timer.stop();

      expect(card.calls, ['clear']);
    });
  });

  group('a launch tidies up after the last one', () {
    test('no session leaves no card', () async {
      // The restore build() fires, not one the test asks for.
      await container().read(timerControllerProvider.notifier).restored;

      expect(
        card.calls,
        ['clear'],
        reason: 'a card outlived the process that owned it',
      );
    });

    test('a restored session gets its card back', () async {
      store.saved = SessionClock(startedAt: t0, taskId: 't1');
      now = t0.add(const Duration(hours: 2));

      await container().read(timerControllerProvider.notifier).restored;

      expect(card.calls, ['show']);
      expect(card.shown.single.startedAt, t0);
    });

    test('a restored paused session gets a paused card', () async {
      store.saved = SessionClock(
        startedAt: t0,
        pausedAt: t0.add(const Duration(minutes: 20)),
        taskId: 't1',
      );
      now = t0.add(const Duration(hours: 2));

      await container().read(timerControllerProvider.notifier).restored;

      expect(card.shown.single.isPaused, isTrue);
    });

    test('Start while the launch is still reading keeps its own card', () async {
      // build() fires the restore and nothing waits for it. Pressing Start
      // in that window used to end with the stale read clearing the card
      // Start had just put up.
      final gate = Completer<void>();
      store.gate = gate;
      final timer = container().read(timerControllerProvider.notifier);

      await timer.start();
      gate.complete();
      await timer.restored;
      await Future<void>.delayed(Duration.zero);

      expect(
        card.calls,
        ['show'],
        reason: 'the launch read took down the card Start had just put up',
      );
    });

    test('restored completes whether or not a session was found', () async {
      final timer = container().read(timerControllerProvider.notifier);
      var landed = false;
      unawaited(timer.restored.then((_) => landed = true));

      await timer.restore();
      await Future<void>.delayed(Duration.zero);

      expect(landed, isTrue);
    });
  });

  group('a tap waits for the session to be read', () {
    late List<String> did;
    late Completer<void> restored;
    late CardTapRouter router;
    var alive = true;

    setUp(() {
      did = [];
      alive = true;
      restored = Completer<void>();
      router = CardTapRouter(
        restored: restored.future,
        alive: () => alive,
        onHome: () => did.add('home'),
        onPause: () => did.add('pause'),
        onResume: () => did.add('resume'),
        onStop: () async => did.add('stop'),
      );
    });

    test('cold start: nothing happens until the restore lands', () async {
      final handled = router.handle('stop');
      await Future<void>.delayed(Duration.zero);

      expect(
        did,
        isEmpty,
        reason: 'stopping a session the app has not read stops nothing',
      );

      restored.complete();
      await handled;

      expect(did, ['home', 'stop']);
    });

    test('warm start: the restore is already done', () async {
      restored.complete();

      await router.handle('pause');

      expect(did, ['home', 'pause']);
    });

    test('resume routes to resume', () async {
      restored.complete();
      await router.handle('resume');
      expect(did, ['home', 'resume']);
    });

    test('tapping the card itself only opens the app', () async {
      restored.complete();
      await router.handle('home');
      expect(did, ['home']);
    });

    test('a word this build does not know does nothing at all', () async {
      restored.complete();
      await router.handle('teleport');
      expect(did, isEmpty, reason: 'it still switched tabs');
    });

    test('a screen that went away while the restore was in flight', () async {
      final handled = router.handle('stop');
      alive = false;
      restored.complete();
      await handled;

      expect(did, isEmpty);
    });
  });

  group('a phone that cannot show a card is never asked twice', () {
    const channel = MethodChannel('sondr/live_activity.test');
    late List<String> asked;

    void answer({required bool supported}) {
      asked = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        asked.add(call.method);
        return call.method == 'supported' ? supported : null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });
    }

    test('below iOS 17 nothing but the question is sent', () async {
      answer(supported: false);
      final activity = ChannelLiveActivity(channel: channel);
      addTearDown(activity.dispose);

      await activity.show(SessionClock(startedAt: t0));
      await activity.clear();
      await activity.ready();

      expect(asked, ['supported'], reason: 'it tried to put up a card anyway');
    });

    test('on iOS 17 the question is asked once, not per call', () async {
      answer(supported: true);
      final activity = ChannelLiveActivity(channel: channel);
      addTearDown(activity.dispose);

      await activity.show(SessionClock(startedAt: t0));
      await activity.clear();
      await activity.ready();

      expect(asked, ['supported', 'show', 'clear', 'ready']);
    });

    test('the session goes over as the stored contract, field for field',
        () async {
      answer(supported: true);
      final activity = ChannelLiveActivity(channel: channel);
      addTearDown(activity.dispose);
      Object? sent;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'show') sent = call.arguments;
        return call.method == 'supported' ? true : null;
      });

      final clock = SessionClock(
        startedAt: t0,
        taskId: 't1',
        taskName: 'Spanish',
        taskSecondsBefore: 7200,
      );
      await activity.show(clock);

      expect(sent, clock.toMap());
    });
  });
}

class _RecordingCard implements LiveActivity {
  final List<String> calls = [];
  final List<SessionClock> shown = [];
  final StreamController<String> taps = StreamController<String>.broadcast();

  @override
  Stream<String> get links => taps.stream;

  @override
  Future<void> show(SessionClock clock) async {
    calls.add('show');
    shown.add(clock);
  }

  @override
  Future<void> clear() async => calls.add('clear');

  @override
  Future<void> ready() async => calls.add('ready');
}

class _MemoryStore implements SessionStore {
  SessionClock? saved;

  /// Holds the FIRST read open, the way a cold launch's does. Only the
  /// first: the reads anything else makes in that window are the point of
  /// the test, and must not queue behind it.
  Completer<void>? gate;

  @override
  Future<SessionClock?> read() async {
    final held = gate;
    if (held != null) {
      gate = null;
      await held.future;
    }
    return saved;
  }

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

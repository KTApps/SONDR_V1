import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/session_log.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/live_activity.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';
import 'package:sondr/features/timer/timer_screen.dart';
import 'package:sondr/shared/ring/segmented_dial.dart';

/// While a session runs or is paused, the dial's centre is that session
/// alone — what the Lock Screen card shows — and the ring never counts it
/// twice, however long the credit takes to land.
void main() {
  final today = DayKey.of(DateTime.now());
  late DateTime now;
  late _Tasks repo;
  late _HangingLog log;

  Future<ProviderContainer> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nowProvider.overrideWithValue(() => now),
          tasksRepositoryProvider.overrideWithValue(repo),
          sessionStoreProvider.overrideWithValue(_NoStore()),
          sessionLogProvider.overrideWithValue(log),
          liveActivityProvider.overrideWithValue(_SilentCard()),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const TimerScreen()),
      ),
    );
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(TimerScreen)));
    c.read(selectedTaskIdProvider.notifier).select('a');
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> after(WidgetTester tester, Duration d) async {
    now = now.add(d);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
  }

  double ringSlice(WidgetTester tester) => tester
      .widget<SegmentedDial>(find.byWidgetPredicate((w) => w is SegmentedDial && w.size > 100))
      .taskTodaySeconds
      .single;

  setUp(() {
    now = DateTime.now();
    // A first session of 21 seconds earlier today.
    repo = _Tasks([Task(id: 'a', name: 'Spanish', secondsByDay: {today: 21})]);
    log = _HangingLog();
  });

  testWidgets('idle: today, as before', (tester) async {
    await pump(tester);
    expect(find.text('0m'), findsOneWidget);
    expect(find.text('today'), findsOneWidget);
  });

  testWidgets('running: this session only, as the card shows it — not today plus the session', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Start'));
    await after(tester, const Duration(seconds: 8));
    expect(find.text('0:08'), findsOneWidget);
    expect(find.text('0:29'), findsNothing);
    expect(find.text(kCentreSessionLabel), findsOneWidget);
    expect(find.text('today'), findsNothing);
    // The ring is a pie of today, so there the session is folded in.
    expect(ringSlice(tester), 29);

    await after(tester, const Duration(minutes: 12, seconds: 32));
    expect(find.text('12:40'), findsOneWidget);
    await after(tester, const Duration(hours: 1));
    expect(find.text('1:12:40'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('paused: the same figure in the same format, frozen, as "paused"', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Start'));
    await after(tester, const Duration(minutes: 12, seconds: 40));
    await tester.tap(find.text('Pause'));
    await after(tester, const Duration(minutes: 5));
    expect(find.text('12:40'), findsOneWidget);
    expect(find.text('12m'), findsNothing);
    expect(find.text(kCentrePausedLabel), findsOneWidget);
    await tester.tap(find.text('Resume'));
    await after(tester, const Duration(seconds: 1));
    expect(find.text('12:41'), findsOneWidget);
    expect(find.text(kCentreSessionLabel), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a tap on a session\'s figure changes nothing', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.text('Start'));
    await after(tester, const Duration(seconds: 8));
    await tester.tap(find.text(kCentreSessionLabel));
    await after(tester, const Duration(seconds: 1));
    expect(find.text(kCentreSessionLabel), findsOneWidget);
    expect(c.read(timerControllerProvider).isRunning, isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Stop: between the credit landing and the session going, the ring counts it once', (tester) async {
    final c = await pump(tester);
    await tester.tap(find.text('Start'));
    await after(tester, const Duration(minutes: 30));
    expect(ringSlice(tester), 21 + 1800);

    // The task takes the credit; the session's own record then hangs, as an
    // offline write does, so the session is still up.
    await tester.tap(find.text('Stop'));
    await tester.pump();
    await tester.pump();
    expect(repo.tasks.single.totalSeconds, 21 + 1800, reason: 'credited');
    expect(log.waiting, isTrue, reason: 'still between credit and discard');
    expect(ringSlice(tester), 21 + 1800, reason: 'counted twice');
    await after(tester, const Duration(seconds: 5));
    expect(ringSlice(tester), 21 + 1800, reason: 'counted twice');

    log.release();
    await tester.pumpAndSettle();
    // The camera is up over Home now; the session is gone beneath it.
    expect(c.read(timerControllerProvider).status, TimerStatus.idle);
    expect(c.read(timerControllerProvider).pendingSecondsFor(repo.tasks.single), 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('pending seconds: the elapsed time until the task carries the session\'s key', () {
    final key = Task.sessionKey(DateTime(2026, 11, 24, 9));
    final state = TimerState(
      status: TimerStatus.running,
      sessionElapsed: const Duration(seconds: 8),
      sessionKey: key,
    );
    const before = Task(id: 'a', name: 'Spanish');
    expect(state.pendingSecondsFor(before), 8);
    final credited = before.crediting(key, 8, DateTime(2026, 11, 24, 9));
    expect(state.pendingSecondsFor(credited), 0);
    expect(state.pendingSecondsFor(null), 0);
    expect(const TimerState().pendingSecondsFor(before), 0);
  });
}

class _Tasks implements TasksRepository {
  _Tasks(this.tasks);
  List<Task> tasks;
  @override
  Future<List<Task>> fetchAll() async => tasks;
  @override
  Future<void> save(Task task) async =>
      tasks = [for (final t in tasks) t.id == task.id ? task : t];
  @override
  Future<void> rename(String taskId, String name) async {}
  @override
  Future<void> delete(String id) async {}
  @override
  Future<Task> create(String name) async => throw UnimplementedError();
}

class _HangingLog implements SessionLog {
  // Made inside the test's own clock, where the record is awaited.
  Completer<void>? _gate;
  bool waiting = false;
  void release() => _gate?.complete();
  @override
  Future<void> record(SessionRecord session) async {
    waiting = true;
    await (_gate = Completer<void>()).future;
    waiting = false;
  }

  @override
  Future<List<SessionRecord>> forTask(String taskId) async => const [];
}

class _NoStore implements SessionStore {
  SessionClock? saved;
  @override
  Future<SessionClock?> read() async => saved;
  @override
  Future<void> write(SessionClock clock) async => saved = clock;
  @override
  Future<void> clear() async => saved = null;
}

class _SilentCard implements LiveActivity {
  @override
  Stream<String> get links => const Stream<String>.empty();
  @override
  Future<void> show(SessionClock clock) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<void> ready() async {}
}

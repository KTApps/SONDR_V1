import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/auth/auth_repository.dart';
import 'package:sondr/features/auth/sign_out_action.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/live_activity.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';

import 'support/app_viewport.dart';

/// Signing out with a session still going.
///
/// It used to take the Lock Screen card away and leave the session
/// running: whoever signed in next found somebody else's timer on Home,
/// and the hours went to their account. Now the session is stopped and
/// credited to the account that earned it — but only once the server has
/// said it has the time, because after the sign-out there is nobody left
/// to retry as.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final t0 = DateTime(2026, 10, 20, 9);

  late DateTime now;
  late _MemoryStore store;
  late _FakeTasks tasks;
  late _RecordingCard card;
  late _RecordingAuth auth;
  late List<String> order;

  Future<ProviderContainer> pump(WidgetTester tester) async {
    late ProviderContainer c;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nowProvider.overrideWithValue(() => now),
          sessionStoreProvider.overrideWithValue(store),
          tasksRepositoryProvider.overrideWithValue(tasks),
          liveActivityProvider.overrideWithValue(card),
          authRepositoryProvider.overrideWithValue(auth),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Consumer(
            builder: (context, ref, _) {
              c = ProviderScope.containerOf(context);
              return const Scaffold(body: Center(child: SignOutAction()));
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  /// A session the app is counting, credited to Spanish.
  Future<TimerController> runningSession(ProviderContainer c) async {
    c.read(selectedTaskIdProvider.notifier).select('t1');
    await c.read(tasksProvider.future);
    final timer = c.read(timerControllerProvider.notifier);
    await timer.restored;
    await timer.start();
    return timer;
  }

  setUp(() {
    now = t0;
    order = [];
    store = _MemoryStore(order);
    tasks = _FakeTasks([const Task(id: 't1', name: 'Spanish')], order);
    card = _RecordingCard(order);
    auth = _RecordingAuth(order);
  });

  group('the prompt', () {
    testWidgets('does not appear when there is no session', (tester) async {
      useReferenceViewport(tester);
      await pump(tester);

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Stop your session?'), findsNothing);
      expect(auth.signedOut, 1, reason: 'it did not sign out');
    });

    testWidgets('names the task and the time for a running session', (
      tester,
    ) async {
      useReferenceViewport(tester);
      final c = await pump(tester);
      await runningSession(c);
      now = t0.add(const Duration(hours: 2, minutes: 15));

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Stop your session?'), findsOneWidget);
      expect(
        find.text(
          'Spanish is still running (2h 15m). Signing out will stop it '
          'and save the time to this account.',
        ),
        findsOneWidget,
      );
      expect(auth.signedOut, 0, reason: 'it signed out before asking');
    });

    testWidgets('says paused, and at what, for a paused session', (
      tester,
    ) async {
      useReferenceViewport(tester);
      final c = await pump(tester);
      final timer = await runningSession(c);
      now = t0.add(const Duration(minutes: 45));
      await timer.pause();
      now = t0.add(const Duration(hours: 5));

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Spanish is paused at 45m. Signing out will stop it and save '
          'the time to this account.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Cancel changes nothing at all', (tester) async {
      useReferenceViewport(tester);
      final c = await pump(tester);
      final timer = await runningSession(c);
      now = t0.add(const Duration(hours: 1));
      order.clear();

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(order, isEmpty, reason: 'cancelling did something');
      expect(timer.state.isRunning, isTrue);
      expect(store.saved, isNotNull);
      expect(auth.signedOut, 0);
      expect(tasks.tasks.single.totalSeconds, 0);
    });
  });

  group('Stop and sign out', () {
    testWidgets('credits, confirms, clears, then signs out — in that order', (
      tester,
    ) async {
      useReferenceViewport(tester);
      final c = await pump(tester);
      await runningSession(c);
      now = t0.add(const Duration(hours: 2));
      order.clear();

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop and sign out'));
      await tester.pumpAndSettle();

      expect(order, ['save', 'card.clear', 'store.clear', 'signOut']);
      expect(tasks.tasks.single.totalSeconds, 2 * 3600);
    });

    testWidgets('a paused session logs the time it stopped at', (tester) async {
      useReferenceViewport(tester);
      final c = await pump(tester);
      final timer = await runningSession(c);
      now = t0.add(const Duration(minutes: 40));
      await timer.pause();
      // Hours go by with it paused; none of them are work.
      now = t0.add(const Duration(hours: 9));

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop and sign out'));
      await tester.pumpAndSettle();

      expect(tasks.tasks.single.totalSeconds, 40 * 60);
      expect(auth.signedOut, 1);
    });

    testWidgets('no camera and no celebration', (tester) async {
      useReferenceViewport(tester);
      final c = await pump(tester);
      await runningSession(c);
      now = t0.add(const Duration(hours: 2));

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop and sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Continue'), findsNothing);
      expect(find.textContaining('Logged'), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget, reason: 'a route opened');
    });
  });

  group('when the save cannot be confirmed', () {
    testWidgets('nothing is thrown away and the reason is shown', (
      tester,
    ) async {
      useReferenceViewport(tester);
      tasks.failSave = true;
      final c = await pump(tester);
      final timer = await runningSession(c);
      now = t0.add(const Duration(hours: 2));
      order.clear();

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop and sign out'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Couldn't save your session. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(auth.signedOut, 0, reason: 'it signed out anyway');
      expect(order, ['save'], reason: 'it cleared something');
      expect(store.saved, isNotNull, reason: 'the session was thrown away');
      expect(timer.state.isRunning, isTrue, reason: 'the clock stopped');
      expect(tasks.tasks.single.totalSeconds, 0);
    });

    testWidgets('the action says so while it waits, and cannot be tapped twice',
        (tester) async {
      useReferenceViewport(tester);
      final hold = Completer<void>();
      tasks.holdSave = hold;
      final c = await pump(tester);
      await runningSession(c);
      now = t0.add(const Duration(hours: 2));

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop and sign out'));
      await tester.pumpAndSettle();

      expect(find.text('Stopping…'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
      // A second tap must not reach the handler at all: with the guard
      // gone it asks again, and the prompt comes back on screen.
      await tester.tap(find.text('Stopping…'));
      await tester.pumpAndSettle();
      expect(
        find.text('Stop your session?'),
        findsNothing,
        reason: 'the busy action was tappable and asked again',
      );
      expect(auth.signedOut, 0);

      hold.complete();
      await tester.pumpAndSettle();
      expect(tasks.saves, 1, reason: 'the second tap started another stop');
      expect(auth.signedOut, 1);
    });

    testWidgets('a save that never answers gives up and keeps the session', (
      tester,
    ) async {
      useReferenceViewport(tester);
      tasks.holdSave = Completer<void>(); // never completed
      final c = await pump(tester);
      final timer = await runningSession(c);
      now = t0.add(const Duration(hours: 2));

      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop and sign out'));
      await tester.pump();
      // Past the ten seconds the save is given.
      await tester.pump(kSignOutSaveTimeout + const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(
        find.text(
          "Couldn't save your session. Check your connection and try again.",
        ),
        findsOneWidget,
      );
      expect(auth.signedOut, 0);
      expect(timer.state.isRunning, isTrue);
      expect(store.saved, isNotNull);
    });
  });

  group('the wording, without a dialog', () {
    test('a running session', () {
      final clock = SessionClock(
        startedAt: t0,
        taskName: 'Learn piano',
      );
      expect(
        signOutPromptBody(clock, t0.add(const Duration(hours: 3, minutes: 8))),
        'Learn piano is still running (3h 8m). Signing out will stop it '
        'and save the time to this account.',
      );
    });

    test('a paused session', () {
      final clock = SessionClock(
        startedAt: t0,
        pausedAt: t0.add(const Duration(minutes: 20)),
        taskName: 'Learn piano',
      );
      expect(
        signOutPromptBody(clock, t0.add(const Duration(hours: 4))),
        'Learn piano is paused at 20m. Signing out will stop it and save '
        'the time to this account.',
      );
    });

    test('a session with no task falls back', () {
      expect(
        signOutPromptBody(SessionClock(startedAt: t0), t0),
        startsWith('Your session is still running (0m).'),
      );
    });
  });
}

class _RecordingAuth implements AuthRepository {
  _RecordingAuth(this.order);

  final List<String> order;
  int signedOut = 0;

  @override
  Future<void> signOut() async {
    order.add('signOut');
    signedOut++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _RecordingCard implements LiveActivity {
  _RecordingCard(this.order);

  final List<String> order;

  @override
  Stream<String> get links => const Stream<String>.empty();

  @override
  Future<void> show(SessionClock clock) async {}

  @override
  Future<void> clear() async => order.add('card.clear');

  @override
  Future<void> ready() async {}
}

class _MemoryStore implements SessionStore {
  _MemoryStore(this.order);

  final List<String> order;
  SessionClock? saved;

  @override
  Future<SessionClock?> read() async => saved;

  @override
  Future<void> write(SessionClock clock) async => saved = clock;

  @override
  Future<void> clear() async {
    order.add('store.clear');
    saved = null;
  }
}

class _FakeTasks implements TasksRepository {
  @override
  Future<void> delete(String taskId) async {}

  _FakeTasks(this.tasks, this.order);

  final List<Task> tasks;
  final List<String> order;

  /// The server refuses the write.
  bool failSave = false;

  /// The server has not answered yet.
  Completer<void>? holdSave;

  int saves = 0;

  @override
  Future<List<Task>> fetchAll() async => tasks;

  @override
  Future<Task> create(String name) async => throw UnimplementedError();

  @override
  Future<void> save(Task task) async {
    order.add('save');
    saves++;
    final hold = holdSave;
    if (hold != null) await hold.future;
    if (failSave) throw StateError('the server refused the write');
    final i = tasks.indexWhere((t) => t.id == task.id);
    if (i >= 0) tasks[i] = task;
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_controller.dart';
import 'package:sondr/features/timer/timer_screen.dart';

/// Where the timer's two controls sit, and what they say.
///
/// The owner's rule: the thing that gets the session going is always on
/// the right, Stop is always on the left, and neither moves when the
/// state changes. A control that moves under the finger between "Pause"
/// and "Start" is a control that gets mis-tapped.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget host(Widget child) => ProviderScope(
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: Center(child: child)),
    ),
  );

  /// The two words on screen, left to right, and where each one is.
  Future<({String left, String right, Map<String, Offset> at})> pump(
    WidgetTester tester,
    TimerStatus status,
  ) async {
    await tester.pumpWidget(
      host(
        TimerControls(
          timer: TimerState(status: status),
          // Idle only splits in two once Start has been tapped; the
          // other two states are always a pair.
          choosing: true,
          onBeginChoice: () {},
          onStart: () {},
          onFocus: () {},
          onResume: () {},
          onPause: () {},
          onStop: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    final words = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data!)
        .toList();
    expect(words.length, 2, reason: '$status should offer two actions');
    final at = {for (final w in words) w: tester.getRect(find.text(w)).center};
    words.sort((a, b) => at[a]!.dx.compareTo(at[b]!.dx));
    return (left: words.first, right: words.last, at: at);
  }

  group('the timer control', () {
    testWidgets('says the right word on each side, in each state', (
      tester,
    ) async {
      final idle = await pump(tester, TimerStatus.idle);
      expect(idle.left, 'Focus');
      expect(idle.right, 'Start');

      final running = await pump(tester, TimerStatus.running);
      expect(running.left, 'Stop');
      expect(running.right, 'Pause');

      final paused = await pump(tester, TimerStatus.paused);
      expect(paused.left, 'Stop');
      // "Start", not "Resume": the word for going again.
      expect(paused.right, 'Start');
    });

    testWidgets('neither control moves as the state changes', (tester) async {
      final idle = await pump(tester, TimerStatus.idle);
      final running = await pump(tester, TimerStatus.running);
      final paused = await pump(tester, TimerStatus.paused);

      // The primary keeps Start's place...
      final primary = idle.at['Start']!.dx;
      expect(running.at['Pause']!.dx, moreOrLessEquals(primary, epsilon: 0.5));
      expect(paused.at['Start']!.dx, moreOrLessEquals(primary, epsilon: 0.5));

      // ...and Stop keeps Focus's.
      final left = idle.at['Focus']!.dx;
      expect(running.at['Stop']!.dx, moreOrLessEquals(left, epsilon: 0.5));
      expect(paused.at['Stop']!.dx, moreOrLessEquals(left, epsilon: 0.5));

      // And they are on the sides the owner asked for.
      expect(primary, greaterThan(left));
    });

    testWidgets('a paused Start is spoken "Resume"', (tester) async {
      await pump(tester, TimerStatus.paused);
      final text = tester.widget<Text>(find.text('Start'));
      expect(text.semanticsLabel, 'Resume');
    });
  });

  group('what a paused Start does', () {
    final t0 = DateTime(2026, 10, 24, 9);
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

    test('it resumes the session that is there, it does not begin one', () async {
      final c = makeContainer();
      final timer = c.read(timerControllerProvider.notifier);
      await timer.start();
      final began = store.saved!.startedAt;

      now = t0.add(const Duration(minutes: 10));
      await timer.pause();

      // Twenty minutes paused, then the right-hand control.
      now = t0.add(const Duration(minutes: 30));
      await timer.start();

      expect(c.read(timerControllerProvider).status, TimerStatus.running);
      expect(
        store.saved!.startedAt,
        began,
        reason: 'a second session was begun instead of going again',
      );
      // And the pause is not credited: ten minutes done, not thirty.
      timer.resyncForTest();
      expect(
        c.read(timerControllerProvider).sessionElapsed,
        const Duration(minutes: 10),
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

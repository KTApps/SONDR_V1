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

/// Where the timer's two controls sit, what they say, and that the one
/// you can see is the one you can press.
///
/// The owner's rule: the control that gets a session going is always on
/// the right, Stop is always on the left, and neither moves between
/// states. A control that shifts under the finger between "Pause" and
/// "Start" is a control that gets mis-tapped — and a place sized by
/// anything other than the words themselves can leave the label drawn
/// outside the thing that answers the tap.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// The control, driven by taps the way the screen drives it.
  Widget host({
    required TimerStatus status,
    required ValueChanged<TimerStatus> onChange,
    List<String>? tapped,
  }) {
    void record(String what, TimerStatus next) {
      tapped?.add(what);
      onChange(next);
    }

    return ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: TimerControls(
              timer: TimerState(status: status),
              choosing: true,
              onBeginChoice: () {},
              onStart: () => record('start', TimerStatus.running),
              onFocus: () => record('focus', TimerStatus.running),
              onPause: () => record('pause', TimerStatus.paused),
              onResume: () => record('resume', TimerStatus.running),
              onStop: () => record('stop', TimerStatus.idle),
            ),
          ),
        ),
      ),
    );
  }

  /// What is on screen, left to right, and where.
  ({String left, String right, Map<String, Offset> at}) read(
    WidgetTester tester,
  ) {
    final words = <String>[];
    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final data = text.data;
      // The other words of a place are laid out but not painted; they
      // are in the tree, and only the visible one counts here.
      if (data != null && !words.contains(data)) words.add(data);
    }
    final shown = words
        .where((w) => tester.any(find.text(w).hitTestable()))
        .toList();
    expect(shown.length, 2, reason: 'two actions should be visible');
    final at = {
      for (final w in shown) w: tester.getRect(find.text(w).first).center,
    };
    shown.sort((a, b) => at[a]!.dx.compareTo(at[b]!.dx));
    return (left: shown.first, right: shown.last, at: at);
  }

  group('the timer control', () {
    testWidgets('says the right word on each side, in each state', (
      tester,
    ) async {
      for (final (status, left, right) in const [
        (TimerStatus.idle, 'Focus', 'Start'),
        (TimerStatus.running, 'Stop', 'Pause'),
        (TimerStatus.paused, 'Stop', 'Start'),
      ]) {
        await tester.pumpWidget(host(status: status, onChange: (_) {}));
        await tester.pumpAndSettle();
        final seen = read(tester);
        expect(seen.left, left, reason: '$status');
        expect(seen.right, right, reason: '$status');
      }
    });

    testWidgets('neither control moves as the state changes', (tester) async {
      final places = <TimerStatus, ({double left, double right})>{};
      for (final status in TimerStatus.values) {
        await tester.pumpWidget(host(status: status, onChange: (_) {}));
        await tester.pumpAndSettle();
        final seen = read(tester);
        places[status] = (
          left: seen.at[seen.left]!.dx,
          right: seen.at[seen.right]!.dx,
        );
      }
      final idle = places[TimerStatus.idle]!;
      for (final status in TimerStatus.values) {
        expect(
          places[status]!.right,
          moreOrLessEquals(idle.right, epsilon: 0.5),
          reason: '$status moved the primary',
        );
        expect(
          places[status]!.left,
          moreOrLessEquals(idle.left, epsilon: 0.5),
          reason: '$status moved the left control',
        );
      }
      expect(idle.right, greaterThan(idle.left));
    });

    testWidgets('every visible control answers its own tap', (tester) async {
      var status = TimerStatus.idle;
      final tapped = <String>[];
      late StateSetter refresh;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            refresh = setState;
            return host(
              status: status,
              tapped: tapped,
              onChange: (next) => refresh(() => status = next),
            );
          },
        ),
      );
      await tester.pumpAndSettle();

      // Start → Pause → Start → Stop, each tap landing on the word on
      // screen at the time.
      await tester.tap(find.text('Start').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pause').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop').hitTestable());
      await tester.pumpAndSettle();

      expect(tapped, ['start', 'pause', 'resume', 'stop']);
    });

    testWidgets('a paused Start is spoken "Resume"', (tester) async {
      await tester.pumpWidget(
        host(status: TimerStatus.paused, onChange: (_) {}),
      );
      await tester.pumpAndSettle();
      final shown = tester
          .widgetList<Text>(find.text('Start'))
          .where((t) => t.semanticsLabel != null);
      expect(shown.single.semanticsLabel, 'Resume');
    });
  });

  group('what a paused Start does', () {
    final t0 = DateTime(2026, 10, 25, 9);
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

    test('it goes again; it does not begin a second session', () async {
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

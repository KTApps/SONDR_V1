import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/features/history/calendar_screen.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/live_activity.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_screen.dart';
import 'package:sondr/shared/ring/segmented_dial.dart';

/// Home during a session: nothing that stays moves, the Last 10 days block
/// fades out of reach, and the milestone countdown takes the heading's line.
void main() {
  final today = DayKey.of(DateTime.now());
  late DateTime now;

  Future<ProviderContainer> pump(WidgetTester tester, {double textScale = 1.0}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nowProvider.overrideWithValue(() => now),
          tasksRepositoryProvider.overrideWithValue(
            _Tasks([Task(id: 'a', name: 'Spanish', secondsByDay: {today: 2 * 3600 + 15 * 60})]),
          ),
          sessionStoreProvider.overrideWithValue(_NoStore()),
          liveActivityProvider.overrideWithValue(_SilentCard()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const TimerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(TimerScreen)));
    c.read(selectedTaskIdProvider.notifier).select('a');
    await tester.pumpAndSettle();
    return c;
  }

  Future<void> settle(WidgetTester tester, [Duration by = const Duration(seconds: 8)]) async {
    now = now.add(by);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Rect hero(WidgetTester tester) =>
      tester.getRect(find.byWidgetPredicate((w) => w is SegmentedDial && w.size > 100));
  double opacityOf(WidgetTester tester, Finder f) => tester
      .widget<AnimatedOpacity>(find.ancestor(of: f, matching: find.byType(AnimatedOpacity)).first)
      .opacity;

  setUp(() => now = DateTime.now());

  for (final ts in [0.824, 1.0, 1.235]) {
    testWidgets('at textScaler $ts nothing that stays moves: idle, running, paused', (tester) async {
      await pump(tester, textScale: ts);
      final idle = (
        label: tester.getRect(find.text('Spanish')),
        dial: hero(tester),
        value: tester.getCenter(find.text('2h 15m')),
        word: tester.getCenter(find.text('today')),
        start: tester.getCenter(find.text('Start')),
      );

      await tester.tap(find.text('Start'));
      await settle(tester);
      final running = (
        label: tester.getRect(find.text('Spanish')),
        dial: hero(tester),
        value: tester.getCenter(find.text('0:08')),
        word: tester.getCenter(find.text(kCentreSessionLabel)),
        pause: tester.getRect(find.text('Pause')),
        stop: tester.getRect(find.text('Stop')),
      );

      await tester.tap(find.text('Pause'));
      await settle(tester);
      final paused = (
        label: tester.getRect(find.text('Spanish')),
        dial: hero(tester),
        value: tester.getCenter(find.text('0:08')),
        word: tester.getCenter(find.text(kCentrePausedLabel)),
        resume: tester.getRect(find.text('Resume')),
        stop: tester.getRect(find.text('Stop')),
      );

      for (final (label, dial) in [(running.label, running.dial), (paused.label, paused.dial)]) {
        expect(label, idle.label, reason: 'task label');
        expect(dial, idle.dial, reason: 'dial');
      }
      // The centre's words change, so their middles are what stay put.
      expect(running.value, idle.value, reason: 'centre figure');
      expect(paused.value, idle.value, reason: 'centre figure');
      expect(running.word, idle.word, reason: 'centre word');
      expect(paused.word, idle.word, reason: 'centre word');
      // Stop does not move; Pause and Resume end at the same place.
      expect(paused.stop, running.stop, reason: 'Stop');
      expect(paused.resume.right, running.pause.right, reason: 'Pause / Resume');
      expect(paused.resume.top, running.pause.top, reason: 'Pause / Resume');
      expect(paused.resume.height, running.pause.height, reason: 'Pause / Resume');
      // Start stands on the same row, centred on the gap Pause and Stop share.
      expect(idle.start.dy, closeTo(running.stop.center.dy, 0.01), reason: 'Start');
      expect(idle.start.dx, closeTo(390 / 2, 0.01), reason: 'Start');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('during a session Last 10 days fades out of reach, keeping its place, and back after', (tester) async {
    await pump(tester);
    final heading = tester.getRect(find.text('Last 10 days'));
    final cta = tester.getRect(find.text('View your progress'));
    expect(opacityOf(tester, find.text('Last 10 days')), 1);

    await tester.tap(find.text('Start'));
    await settle(tester);
    final fade = tester.widget<AnimatedOpacity>(
      find.ancestor(of: find.text('View your progress'), matching: find.byType(AnimatedOpacity)).first,
    );
    expect(fade.opacity, 0);
    expect(fade.duration, const Duration(milliseconds: 300));
    expect(fade.curve, Curves.easeOut);
    expect(opacityOf(tester, find.text('Last 10 days')), 0);
    for (final day in tester.widgetList<SegmentedDial>(find.byWidgetPredicate((w) => w is SegmentedDial && w.size < 100))) {
      expect(day.compact, isTrue);
    }
    expect(tester.getRect(find.text('Last 10 days')), heading, reason: 'its space is kept');
    expect(tester.getRect(find.text('View your progress')), cta, reason: 'its space is kept');
    await tester.tap(find.text('View your progress'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsNothing, reason: 'not tappable');

    await tester.tap(find.text('Pause'));
    await settle(tester);
    expect(opacityOf(tester, find.text('Last 10 days')), 0, reason: 'paused is still a session');

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    // Under a minute: logged, no camera.
    expect(opacityOf(tester, find.text('Last 10 days')), 1);
    expect(opacityOf(tester, find.byKey(kHomeCountdownKey)), 0);
    await tester.tap(find.text('View your progress'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);
    // The "Logged" line clears itself.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the countdown: the card\'s words, centred, on the heading\'s line, in the supporting tone', (tester) async {
    await pump(tester);
    expect(opacityOf(tester, find.byKey(kHomeCountdownKey)), 0, reason: 'idle: not shown');

    await tester.tap(find.text('Start'));
    await settle(tester, const Duration(minutes: 5));
    // 2h 15m before; 5 minutes in: 17h 40m to go.
    expect(find.text('17 hrs, 40 min to your next milestone'), findsOneWidget);
    expect(opacityOf(tester, find.byKey(kHomeCountdownKey)), 1);
    final countdown = tester.getRect(find.byKey(kHomeCountdownKey));
    final heading = tester.getRect(find.text('Last 10 days'));
    expect(countdown.center.dy, closeTo(heading.center.dy, 0.01));
    expect(countdown.center.dx, closeTo(390 / 2, 0.01));
    final style = tester.widget<Text>(find.byKey(kHomeCountdownKey)).style!;
    final hint = Theme.of(tester.element(find.byKey(kHomeCountdownKey))).textTheme.bodyMedium!;
    expect(style.fontSize, hint.fontSize);
    expect(style.fontWeight, hint.fontWeight);
    expect(style.color, GreyscaleTokens.of(tester.element(find.byKey(kHomeCountdownKey))).textSecondary);

    // Moves while running…
    await settle(tester, const Duration(minutes: 1));
    expect(find.text('17 hrs, 39 min to your next milestone'), findsOneWidget);
    // …and stands still while paused.
    await tester.tap(find.text('Pause'));
    await settle(tester, const Duration(minutes: 10));
    expect(find.text('17 hrs, 39 min to your next milestone'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
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

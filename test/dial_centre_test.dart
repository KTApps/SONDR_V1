import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/core/utils/figma_scale.dart';
import 'package:sondr/features/habits/habits_screen.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/centre_period.dart';
import 'package:sondr/features/timer/home_metrics.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';
import 'package:sondr/features/timer/timer_screen.dart';
import 'package:sondr/shared/ring/segmented_dial.dart';

class _FakeTasks implements TasksRepository {
  _FakeTasks(this.tasks);
  final List<Task> tasks;
  @override
  Future<List<Task>> fetchAll() async => tasks;
  @override
  Future<void> delete(String id) async {}
  @override
  Future<Task> create(String name) async => throw UnimplementedError();
  @override
  Future<void> save(Task task) async {}
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

/// The dial's centre answers a tap as well as a swipe, and says so by
/// changing: a cross-fade in place, with nothing moving and nothing else
/// on the dial disturbed.
void main() {
  final today = DayKey.of(DateTime.now());

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    List<Task> tasks = const [],
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tasksRepositoryProvider.overrideWithValue(_FakeTasks(tasks)),
          sessionStoreProvider.overrideWithValue(_NoStore()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const TimerScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(tester.element(find.byType(TimerScreen)));
  }

  /// The hero dial, not the ten day dials beneath it.
  Finder heroDial() =>
      find.byWidgetPredicate((w) => w is SegmentedDial && w.size > 100);

  Task spanish() =>
      Task(id: 'a', name: 'Spanish', secondsByDay: {today: 2 * 3600 + 15 * 60});

  testWidgets('a tap on the centre changes the window, and so does a swipe', (
    tester,
  ) async {
    final c = await pump(tester, tasks: [spanish()]);
    expect(find.text('today'), findsOneWidget);
    expect(c.read(centrePeriodProvider), CentrePeriod.today);

    await tester.tap(find.text('today'));
    await tester.pumpAndSettle();
    expect(c.read(centrePeriodProvider), CentrePeriod.month);
    expect(find.text('this month'), findsOneWidget);
    expect(find.text('today'), findsNothing);

    // The swipe still does it too.
    await tester.drag(find.text('this month'), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(c.read(centrePeriodProvider), CentrePeriod.today);
    expect(find.text('today'), findsOneWidget);
  });

  testWidgets('the change is a cross-fade in place — nothing moves', (
    tester,
  ) async {
    await pump(tester, tasks: [spanish()]);
    final before = tester.getRect(find.text('2h 15m'));
    await tester.tap(find.text('today'));
    await tester.pump(); // the rebuild that starts the fade
    // Halfway: both words are on screen, each part-way faded, and the
    // figure has not moved.
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('today'), findsOneWidget);
    expect(find.text('this month'), findsOneWidget);
    final opacities = tester
        .widgetList<FadeTransition>(find.byType(FadeTransition))
        .map((f) => f.opacity.value)
        .toList();
    expect(opacities.any((o) => o > 0 && o < 1), isTrue, reason: 'mid-fade');
    await tester.pumpAndSettle();
    expect(tester.getRect(find.text('2h 15m')), before);
  });

  testWidgets('a tap mid-fade reverses it cleanly', (tester) async {
    final c = await pump(tester, tasks: [spanish()]);
    await tester.tap(find.text('today'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    // Back again, mid-fade.
    await tester.tap(find.text('this month'));
    await tester.pumpAndSettle();
    expect(c.read(centrePeriodProvider), CentrePeriod.today);
    // One word, one figure: nothing stacked up.
    expect(find.text('today'), findsOneWidget);
    expect(find.text('this month'), findsNothing);
    expect(find.text('2h 15m'), findsOneWidget);
  });

  testWidgets('with no tasks the centre does nothing', (tester) async {
    final c = await pump(tester);
    expect(find.text('add a task'), findsOneWidget);
    await tester.tap(find.text('add a task'));
    await tester.pumpAndSettle();
    expect(c.read(centrePeriodProvider), CentrePeriod.today);
    expect(find.text('add a task'), findsOneWidget);
  });

  testWidgets('the inner ring still opens Habits', (tester) async {
    await pump(tester, tasks: [spanish()]);
    final dial = tester.getRect(heroDial());
    final sd = tester.widget<SegmentedDial>(heroDial());
    // A point on the inner ring's band, straight above the centre.
    final innerR = sd.size * 110 / 312;
    await tester.tapAt(dial.center.translate(0, -innerR));
    await tester.pumpAndSettle();
    expect(find.byType(HabitsScreen), findsOneWidget);
  });

  testWidgets('the tap target is a thumb wide, and nowhere near the ring', (
    tester,
  ) async {
    for (final ts in [0.824, 1.0, 1.235]) {
      await pump(tester, tasks: [spanish()], textScale: ts);
      final scale = figmaScale(tester.element(find.byType(TimerScreen)));
      final target = tester.getRect(
        find
            .ancestor(of: find.text('2h 15m'), matching: find.byType(Padding))
            .first,
      );
      expect(
        target.height,
        greaterThanOrEqualTo(kDialCentreTarget * scale - 0.5),
        reason: 'tap target at $ts',
      );
      // The inner ring's band starts here; the target must not reach it.
      final sd = tester.widget<SegmentedDial>(heroDial());
      final bandInner = sd.size * 110 / 312 - sd.size * 22 / 312 / 2 - 12;
      expect(target.height / 2, lessThan(bandInner), reason: 'vertical at $ts');
      expect(target.width / 2, lessThan(bandInner), reason: 'horizontal at $ts');
    }
  });

  testWidgets('the dots are gone, and nothing below the dial moved', (
    tester,
  ) async {
    await pump(tester, tasks: [spanish()]);
    final scale = figmaScale(tester.element(find.byType(TimerScreen)));
    // Everything in this stack is positioned from its top, so nothing
    // below the dots could move when they went — these are the same
    // numbers the layout declares.
    expect(tester.getRect(heroDial()).top, closeTo(152 * scale, 0.5));
    expect(
      tester.getRect(find.text('Last 10 days')).top,
      closeTo(kHomeLastTenTop * scale, 1.0),
    );
    // Nothing is left of the dots: two 6pt circles in a row.
    final dots = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.constraints?.maxWidth == 6 &&
          w.constraints?.maxHeight == 6,
    );
    expect(dots, findsNothing);
  });
}

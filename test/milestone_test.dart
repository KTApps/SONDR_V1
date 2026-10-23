import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/features/milestone/milestone_celebration.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/timer_controller.dart';

/// Minimal repository with a single, precisely-seeded task.
class _FakeTasksRepo implements TasksRepository {
  @override
  Future<void> delete(String taskId) async {}

  _FakeTasksRepo(this.tasks);
  final List<Task> tasks;

  @override
  Future<List<Task>> fetchAll() async => tasks;

  @override
  Future<Task> create(String name) async {
    final t = Task(id: 'new', name: name);
    tasks.add(t);
    return t;
  }

  @override
  Future<void> save(Task task) async {
    final i = tasks.indexWhere((t) => t.id == task.id);
    if (i >= 0) {
      tasks[i] = task;
    } else {
      tasks.add(task);
    }
  }
}

ProviderContainer _containerWith(Task seed) {
  final c = ProviderContainer(
    overrides: [
      tasksRepositoryProvider.overrideWithValue(_FakeTasksRepo([seed])),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() async {
  final today = DayKey.of(DateTime.now());

  test('stopping across 20h reports the first milestone', () async {
    // One second short of the first milestone.
    final seed = Task(
      id: 't',
      name: 'Spanish',
      secondsByDay: {today: 20 * 3600 - 1},
    );
    final c = _containerWith(seed);
    await c.read(tasksProvider.future);
    c.read(selectedTaskIdProvider.notifier).select('t');

    final controller = c.read(timerControllerProvider.notifier);
    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final outcome = await controller.stop();

    expect(outcome.reachedMilestone, isTrue);
    expect(outcome.milestoneHours, 20);
    expect(outcome.isFirstMilestone, isTrue);
    expect(outcome.totalHours, 20);
  });

  test('the hours a post records are FLOORED, not rounded', () async {
    // 19h 59m on the task, and a second of session on top. Rounded, the
    // post recorded 20 hours on a task that had logged 19.
    Future<int> hoursAfterStopping(int seeded) async {
      final c = _containerWith(
        Task(id: 't', name: 'Spanish', secondsByDay: {today: seeded}),
      );
      await c.read(tasksProvider.future);
      c.read(selectedTaskIdProvider.notifier).select('t');
      final controller = c.read(timerControllerProvider.notifier);
      await controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final outcome = await controller.stop();
      return outcome.totalHours;
    }

    expect(await hoursAfterStopping(19 * 3600 + 59 * 60), 19);
    expect(await hoursAfterStopping(20 * 3600 - 1), 20);
    expect(await hoursAfterStopping(20 * 3600 + 59 * 60 + 57), 20);
  });

  test('stopping without crossing a boundary reports no milestone', () async {
    final seed = Task(id: 't', name: 'Piano', secondsByDay: {today: 3600});
    final c = _containerWith(seed);
    await c.read(tasksProvider.future);
    c.read(selectedTaskIdProvider.notifier).select('t');

    final controller = c.read(timerControllerProvider.notifier);
    await controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final outcome = await controller.stop();

    expect(outcome.loggedSeconds, greaterThanOrEqualTo(1));
    expect(outcome.reachedMilestone, isFalse);
    expect(outcome.milestoneHours, isNull);
  });

  /// The celebration, with and without an account.
  Future<void> pumpCelebration(
    WidgetTester tester, {
    required bool guest,
    bool isFirst = true,
    int milestoneHours = 20,
    String taskName = 'Spanish',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [isGuestProvider.overrideWithValue(guest)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MilestoneCelebrationScreen(
            taskId: 'spanish',
            taskName: taskName,
            milestoneHours: milestoneHours,
            totalHours: milestoneHours + 1,
            sessionSeconds: 3600,
            cumulativeSeconds: milestoneHours * 3600,
            isFirst: isFirst,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('signed in, the celebration has one way on', (tester) async {
    await pumpCelebration(tester, guest: false);
    expect(find.text('Congratulations!'), findsOneWidget);
    expect(find.text('20 hrs'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
    // "Not now" is gone: the camera's own Skip is the way past, and two
    // refusals before the thing has been seen was one too many.
    expect(find.text('Not now'), findsNothing);
    expect(find.text('Share this milestone'), findsNothing);
    expect(find.text('Create account'), findsNothing);
  });

  testWidgets('later milestones celebrate the same way', (tester) async {
    await pumpCelebration(
      tester,
      guest: false,
      isFirst: false,
      milestoneHours: 40,
      taskName: 'Piano',
    );
    expect(find.textContaining('another milestone'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('a guest is offered the account as well as the camera', (
    tester,
  ) async {
    await pumpCelebration(tester, guest: true);
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.textContaining('Create an account to keep'), findsOneWidget);
    // Continue leads first; the account is the quiet one under it.
    expect(
      tester.getRect(find.text('Continue')).bottom,
      lessThan(tester.getRect(find.text('Create account')).top),
    );
    final account = tester.widget<Text>(find.text('Create account'));
    expect(account.style!.fontWeight, FontWeight.w400);
  });

  testWidgets('a guest\'s "Create account" opens the prompt', (tester) async {
    await pumpCelebration(tester, guest: true);
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Keep your progress safe'), findsOneWidget);
    expect(find.textContaining('share milestones with friends'), findsOneWidget);
  });

  testWidgets('no Material TextButton survives in the flow', (tester) async {
    for (final guest in [false, true]) {
      await pumpCelebration(tester, guest: guest);
      expect(
        find.byType(TextButton),
        findsNothing,
        reason: 'a TextButton came back (guest: $guest)',
      );
    }
  });
}

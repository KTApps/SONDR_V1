import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/features/milestone/milestone_celebration.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';
import 'package:sondr/features/tasks/tasks_repository.dart';
import 'package:sondr/features/timer/timer_controller.dart';

/// Minimal repository with a single, precisely-seeded task.
class _FakeTasksRepo implements TasksRepository {
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
  final c = ProviderContainer(overrides: [
    tasksRepositoryProvider.overrideWithValue(_FakeTasksRepo([seed])),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
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
    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    final outcome = await controller.stop();

    expect(outcome.reachedMilestone, isTrue);
    expect(outcome.milestoneHours, 20);
    expect(outcome.isFirstMilestone, isTrue);
    expect(outcome.totalHours, 20);
  });

  test('stopping without crossing a boundary reports no milestone', () async {
    final seed = Task(id: 't', name: 'Piano', secondsByDay: {today: 3600});
    final c = _containerWith(seed);
    await c.read(tasksProvider.future);
    c.read(selectedTaskIdProvider.notifier).select('t');

    final controller = c.read(timerControllerProvider.notifier);
    controller.start();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final outcome = await controller.stop();

    expect(outcome.loggedSeconds, greaterThanOrEqualTo(1));
    expect(outcome.reachedMilestone, isFalse);
    expect(outcome.milestoneHours, isNull);
  });

  testWidgets('celebration screen offers the share-or-not choice',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MilestoneCelebrationScreen(
            taskName: 'Spanish',
            milestoneHours: 20,
            totalHours: 21,
            isFirst: true,
            canShare: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Congratulations!'), findsOneWidget);
    expect(find.text('20 hrs'), findsOneWidget);
    expect(find.text('Share with a photo'), findsOneWidget);
    expect(find.text('Share without a photo'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('celebration without sharing just shows Done', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: MilestoneCelebrationScreen(
            taskName: 'Piano',
            milestoneHours: 40,
            totalHours: 41,
            isFirst: false,
            canShare: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Share with a photo'), findsNothing);
    expect(find.text('Done'), findsOneWidget);
  });
}

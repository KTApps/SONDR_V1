import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/features/tasks/models/task.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';

void main() {
  group('Task milestone maths', () {
    final now = DateTime(2026, 6, 1, 10);
    final today = DayKey.of(now);

    test('totals and today derive from the per-day map', () {
      final task = Task(
        id: 't',
        name: 'Spanish',
        secondsByDay: {
          DayKey.of(now.subtract(const Duration(days: 3))): 3600,
          today: 1800,
        },
      );
      expect(task.totalSeconds, 5400);
      expect(task.todaySeconds(now), 1800);
    });

    test('first milestone is 20h; progress fills within the band', () {
      final task = Task(
        id: 't',
        name: 'Spanish',
        secondsByDay: {today: 10 * 3600}, // 10h
      );
      expect(task.milestonesReached, 0);
      expect(task.activeMilestoneHours, 20);
      expect(task.milestoneProgress, closeTo(0.5, 1e-9));
    });

    test('crossing 20h advances to the next 20h band', () {
      final task = Task(
        id: 't',
        name: 'Golf',
        secondsByDay: {today: 25 * 3600}, // 25h
      );
      expect(task.milestonesReached, 1);
      expect(task.activeMilestoneHours, 40);
      expect(task.milestoneProgress, closeTo(0.25, 1e-9)); // 5h into the band
    });

    test('addingSeconds accumulates onto the right day immutably', () {
      const task = Task(id: 't', name: 'Piano');
      final updated = task.addingSeconds(1800, now);
      expect(task.totalSeconds, 0); // original untouched
      expect(updated.todaySeconds(now), 1800);
    });

    test('monthSeconds sums the calendar month, excludes other months', () {
      final task = Task(
        id: 't',
        name: 'Spanish',
        secondsByDay: {
          DayKey.of(DateTime(2026, 6, 1)): 3600,
          DayKey.of(DateTime(2026, 6, 20)): 1800,
          DayKey.of(DateTime(2026, 5, 31)): 7200, // previous month
        },
      );
      expect(task.monthSeconds(now), 5400);
    });

    test('firstMilestoneProgress fills toward 20h and clamps past it', () {
      expect(
        Task(id: 't', name: 'x', secondsByDay: {today: 10 * 3600})
            .firstMilestoneProgress,
        closeTo(0.5, 1e-9),
      );
      expect(
        Task(id: 't', name: 'x', secondsByDay: {today: 25 * 3600})
            .firstMilestoneProgress,
        1.0,
      );
    });
  });

  group('TasksController', () {
    test('logSeconds persists effort to the selected task for today', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Realise the async list.
      final tasks = await container.read(tasksProvider.future);
      final spanish = tasks.firstWhere((t) => t.name == 'Spanish');
      final before = spanish.totalSeconds;

      await container
          .read(tasksProvider.notifier)
          .logSeconds(spanish.id, 1800, DateTime.now());

      final after = container
          .read(tasksProvider)
          .value!
          .firstWhere((t) => t.id == spanish.id);
      expect(after.totalSeconds, before + 1800);
    });
  });
}

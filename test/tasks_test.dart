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

    test('milestoneProgress climbs, resets on each 20h, and climbs again', () {
      double progressAt(int hours) => Task(
        id: 't',
        name: 'x',
        secondsByDay: {today: hours * 3600},
      ).milestoneProgress;

      expect(progressAt(0), closeTo(0.0, 1e-9));
      expect(progressAt(10), closeTo(0.5, 1e-9));
      // The reset is the point: a task at exactly 20h reads empty, not full,
      // and starts climbing toward 40h.
      expect(progressAt(20), closeTo(0.0, 1e-9));
      expect(progressAt(25), closeTo(0.25, 1e-9));
      expect(progressAt(40), closeTo(0.0, 1e-9));
      expect(progressAt(47), closeTo(0.35, 1e-9));
    });

    test('wholeHours floors, so the figure never claims a milestone early', () {
      int hoursFor(int seconds) =>
          Task(id: 't', name: 'x', secondsByDay: {today: seconds}).wholeHours;

      // 90s short of 20h — the ring is all but full, but the milestone has
      // not been reached, so the figure must still read 19.
      expect(hoursFor(20 * 3600 - 90), 19);
      // Reached for real.
      expect(hoursFor(20 * 3600), 20);
      // Never rounds up mid-block either.
      expect(hoursFor((23 * 3600) + (48 * 60)), 23);
    });

    test('milestonesReached is unchanged by the ring behaviour', () {
      int reachedAt(int hours) => Task(
        id: 't',
        name: 'x',
        secondsByDay: {today: hours * 3600},
      ).milestonesReached;

      // Guards the 40h/60h celebrations, which key off this and must keep
      // firing however the ring chooses to draw itself.
      expect(reachedAt(19), 0);
      expect(reachedAt(20), 1);
      expect(reachedAt(25), 1);
      expect(reachedAt(40), 2);
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

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/features/habits/habits_providers.dart';

void main() {
  String todayKey() => DayKey.of(DateTime.now());
  String yesterdayKey() =>
      DayKey.of(DateTime.now().subtract(const Duration(days: 1)));

  group('HabitsController', () {
    test('toggle flips today\'s completion and the inner-ring progress',
        () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);

      final state = await c.read(habitsProvider.future);
      final today = state.days[todayKey()]!;
      final before = today.completed; // seeded: 2 done
      final firstUnchecked =
          today.ticks.firstWhere((t) => !t.done).habitId;

      await c.read(habitsProvider.notifier).toggle(firstUnchecked);

      final after = c.read(todayHabitsProvider)!;
      expect(after.completed, before + 1);
      expect(c.read(habitsTodayProgressProvider),
          closeTo(after.completed / after.total, 1e-9));
    });

    test('adding a habit appears today, unchecked', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(habitsProvider.future);

      await c.read(habitsProvider.notifier).addHabit('Read 10 pages');
      final today = c.read(todayHabitsProvider)!;

      expect(today.ticks.map((t) => t.name), contains('Read 10 pages'));
      expect(today.ticks.last.done, isFalse);
    });

    test('removing a habit drops it today but past days keep it (immutable)',
        () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final state = await c.read(habitsProvider.future);

      final victim = state.liveList.first;
      final yKeyBefore = state.days[yesterdayKey()]!;
      expect(yKeyBefore.ticks.any((t) => t.habitId == victim.id), isTrue);

      await c.read(habitsProvider.notifier).removeHabit(victim.id);
      final next = c.read(habitsProvider).value!;

      // Gone from today + live list...
      expect(next.liveList.any((h) => h.id == victim.id), isFalse);
      expect(
        next.days[todayKey()]!.ticks.any((t) => t.habitId == victim.id),
        isFalse,
      );
      // ...but yesterday's frozen snapshot is unchanged.
      expect(
        next.days[yesterdayKey()]!.ticks.any((t) => t.habitId == victim.id),
        isTrue,
      );
    });
  });
}

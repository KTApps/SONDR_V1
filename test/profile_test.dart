import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/profile/profile_providers.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';

void main() {
  group('Profile effort summary', () {
    test('lifetime duration sums every task total', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final tasks = await container.read(tasksProvider.future);
      final expected = tasks.fold<int>(0, (s, t) => s + t.totalSeconds);

      expect(container.read(lifetimeDurationProvider).inSeconds, expected);
    });

    test('logging 20h adds one milestone and lifts lifetime by 20h', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final tasks = await container.read(tasksProvider.future);
      final baseSeconds = container.read(lifetimeDurationProvider).inSeconds;
      final baseMilestones = container.read(milestonesReachedProvider);

      await container
          .read(tasksProvider.notifier)
          .logSeconds(tasks.first.id, 20 * 3600, DateTime.now());

      // floor(total/20h) gains exactly one band when 20h is added.
      expect(container.read(milestonesReachedProvider), baseMilestones + 1);
      expect(
        container.read(lifetimeDurationProvider).inSeconds,
        baseSeconds + 20 * 3600,
      );
    });
  });
}

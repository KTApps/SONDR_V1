import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/profile/profile_providers.dart';
import 'package:sondr/features/profile/public_profile.dart';
import 'package:sondr/features/tasks/models/task.dart';

Task _task(int seconds) =>
    Task(id: 't', name: 't', secondsByDay: {'2026-10-01': seconds});

/// Hours are FLOORED wherever they are printed, and the time left is
/// rounded UP to the minute. An hour you have not finished is not an hour,
/// and a milestone is never promised sooner than it will arrive.
void main() {
  group('the hours figure', () {
    test('floors: 19h 59m is nineteen hours', () {
      expect(wholeHoursOf([_task(19 * 3600 + 59 * 60)]), 19);
      expect(wholeHoursOf([_task(19 * 3600 + 59 * 60 + 59)]), 19);
      expect(wholeHoursOf([_task(20 * 3600)]), 20);
      expect(wholeHoursOf([_task(0)]), 0);
    });

    test('the published copy carries the exact figure, not the floor', () {
      final seconds = lifetimeSecondsOf([_task(19 * 3600 + 59 * 60)]);
      expect(seconds, 19 * 3600 + 59 * 60);
      const published = PublicProfile(
        uid: 'them',
        handle: 'cass',
        displayName: 'Cass',
        hours: 19,
        seconds: 19 * 3600 + 59 * 60,
      );
      expect(published.wholeHours, 19);
      expect(published.toMap()['seconds'], 19 * 3600 + 59 * 60);
    });

    test('a document written before the seconds existed still reads', () {
      final old = PublicProfile.fromMap('them', const {
        'handle': 'cass',
        'displayName': 'Cass',
        'hours': 41,
      });
      expect(old.seconds, isNull);
      expect(old.wholeHours, 41);
      // And one written since prefers the exact figure.
      final now = PublicProfile.fromMap('them', const {
        'handle': 'cass',
        'displayName': 'Cass',
        'hours': 41,
        'seconds': 41 * 3600 + 3000,
      });
      expect(now.wholeHours, 41);
    });
  });

  group('the time left', () {
    test('hours and minutes', () {
      expect(remainingLabel(1 * 3600 + 12 * 60), '1h 12m');
      expect(remainingLabel(45 * 60), '45m');
      expect(remainingLabel(2 * 3600), '2h');
    });

    test('rounds UP to the minute — never a milestone promised early', () {
      expect(remainingLabel(1 * 3600 + 1), '1h 1m');
      expect(remainingLabel(61), '2m');
      expect(remainingLabel(60), '1m');
    });

    test('the last minute says so rather than counting it down', () {
      expect(remainingLabel(59), '<1m');
      expect(remainingLabel(1), '<1m');
      expect(remainingLabel(0), '<1m');
    });
  });
}

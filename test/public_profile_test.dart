import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/auth/models/profile.dart';
import 'package:sondr/features/friends/models/friendship.dart';
import 'package:sondr/features/profile/friend_mirror.dart';
import 'package:sondr/features/profile/public_profile.dart';
import 'package:sondr/features/tasks/models/task.dart';

Task _task(String id, {required int seconds}) =>
    Task(id: id, name: id, secondsByDay: {'2026-10-01': seconds});

Profile _profile({String username = 'ada', String displayName = 'Ada'}) =>
    Profile(uid: 'me', username: username, displayName: displayName);

PublicProfile _published({
  String handle = 'ada',
  String displayName = 'Ada',
  int hours = 20,
}) => PublicProfile(
  uid: 'me',
  handle: handle,
  displayName: displayName,
  hours: hours,
);

Friendship _friendship(
  String other, {
  bool accepted = true,
  String requestedBy = 'me',
}) => Friendship(
  id: Friendship.pairId('me', other),
  users: ['me', other]..sort(),
  requestedBy: requestedBy,
  status: accepted ? FriendshipStatus.accepted : FriendshipStatus.pending,
  profiles: const {},
);

void main() {
  group('what gets published', () {
    test('whole hours across every task, rounded down', () {
      expect(wholeHoursOf([_task('a', seconds: 3599)]), 0);
      expect(wholeHoursOf([_task('a', seconds: 3600)]), 1);
      expect(
        wholeHoursOf([_task('a', seconds: 20 * 3600), _task('b', seconds: 1800)]),
        20,
      );
      expect(wholeHoursOf(const []), 0);
    });

    test('nothing at all without a handle — the rules would refuse it', () {
      expect(
        profileToPublish(
          uid: 'me',
          profile: _profile(username: ''),
          tasks: [_task('a', seconds: 3600)],
          published: null,
        ),
        isNull,
      );
      expect(
        profileToPublish(
          uid: 'me',
          profile: null,
          tasks: [_task('a', seconds: 3600)],
          published: null,
        ),
        isNull,
      );
    });

    test('the first publish says the handle, the name and the hours', () {
      final mine = profileToPublish(
        uid: 'me',
        profile: _profile(),
        tasks: [_task('a', seconds: 20 * 3600 + 60)],
        published: null,
      );
      expect(mine, isNotNull);
      expect(mine!.handle, 'ada');
      expect(mine.displayName, 'Ada');
      expect(mine.hours, 20);
      expect(mine.toMap(), {'handle': 'ada', 'displayName': 'Ada', 'hours': 20});
    });

    test('an unchanged figure writes nothing, however often it is asked', () {
      for (var i = 0; i < 5; i++) {
        expect(
          profileToPublish(
            uid: 'me',
            profile: _profile(),
            tasks: [_task('a', seconds: 20 * 3600 + 59 * 60)],
            published: _published(hours: 20),
          ),
          isNull,
          reason: 'still 20 whole hours',
        );
      }
    });

    test('a changed hour, name or handle does write', () {
      PublicProfile? publish({int seconds = 21 * 3600, Profile? who}) =>
          profileToPublish(
            uid: 'me',
            profile: who ?? _profile(),
            tasks: [_task('a', seconds: seconds)],
            published: _published(hours: 20),
          );
      expect(publish()?.hours, 21);
      expect(
        publish(seconds: 20 * 3600, who: _profile(displayName: 'Ada L'))
            ?.displayName,
        'Ada L',
      );
      expect(
        publish(seconds: 20 * 3600, who: _profile(username: 'adalovelace'))
            ?.handle,
        'adalovelace',
      );
    });

    test('a label and a ring letter, falling back to the handle', () {
      expect(_published(displayName: 'Ada').label, 'Ada');
      expect(_published(displayName: '').label, '@ada');
      expect(_published(displayName: 'ada').initial, 'A');
      expect(_published(displayName: '', handle: 'zoe').initial, 'Z');
      expect(_published(displayName: '', handle: '').initial, '');
    });
  });

  group('the friend mirror', () {
    test('writes the halves missing for my accepted friendships', () {
      expect(
        missingMirrorHalves(
          uid: 'me',
          friendships: [_friendship('a'), _friendship('b')],
          have: const {},
        ),
        ['a', 'b'],
      );
    });

    test('leaves alone what is already there', () {
      expect(
        missingMirrorHalves(
          uid: 'me',
          friendships: [_friendship('a'), _friendship('b')],
          have: const {'a'},
        ),
        ['b'],
      );
      expect(
        missingMirrorHalves(
          uid: 'me',
          friendships: [_friendship('a')],
          have: const {'a'},
        ),
        isEmpty,
      );
    });

    test('a pending request is not a friendship and is never mirrored', () {
      expect(
        missingMirrorHalves(
          uid: 'me',
          friendships: [
            _friendship('a', accepted: false),
            _friendship('b', accepted: false, requestedBy: 'b'),
          ],
          have: const {},
        ),
        isEmpty,
      );
    });

    test('each pair once', () {
      expect(
        missingMirrorHalves(
          uid: 'me',
          friendships: [_friendship('a'), _friendship('a')],
          have: const {},
        ),
        ['a'],
      );
    });

    test('the pair id is the sorted join, from either side', () {
      expect(Friendship.pairId('b', 'a'), 'a__b');
      expect(Friendship.pairId('a', 'b'), Friendship.pairId('b', 'a'));
    });
  });
}

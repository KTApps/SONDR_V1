import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/friends/friends_repository.dart';
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
  int? seconds,
  double ringProgress = 0,
}) => PublicProfile(
  uid: 'me',
  handle: handle,
  displayName: displayName,
  hours: hours,
  seconds: seconds,
  ringProgress: ringProgress,
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

/// A publish target that remembers, and can be told to fail the way
/// Firestore does: a cache read for a document the device does not hold
/// THROWS, it does not come back empty.
class _FakeTarget implements ProfilePublishTarget {
  _FakeTarget({this.stored, this.readThrows = false});

  PublicProfile? stored;
  final bool readThrows;
  final published = <PublicProfile>[];

  @override
  String get uid => 'me';

  @override
  Future<PublicProfile?> publishedCopy() async {
    if (readThrows) throw StateError('Failed to get document from cache.');
    return stored;
  }

  @override
  Future<void> publish(PublicProfile profile) async {
    published.add(profile);
    stored = profile;
  }
}

void main() {
  setUp(resetPublishedProfileMemory);

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
      expect(mine.toMap(), {
        'handle': 'ada',
        'displayName': 'Ada',
        'hours': 20,
        'seconds': 20 * 3600 + 60,
        'ringProgress': mine.ringProgress,
      });
    });

    test('an unchanged figure writes nothing, however often it is asked', () {
      for (var i = 0; i < 5; i++) {
        expect(
          profileToPublish(
            uid: 'me',
            profile: _profile(),
            tasks: [_task('a', seconds: 20 * 3600 + 59 * 60)],
            published: _published(
              hours: 20,
              seconds: 20 * 3600 + 59 * 60,
              ringProgress: ringProgressOf([
                _task('a', seconds: 20 * 3600 + 59 * 60),
              ]),
            ),
          ),
          isNull,
          reason: 'still 20 whole hours, and the ring has not moved',
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

  group('publishing', () {
    test('a first publish writes, because nothing is published yet', () async {
      final target = _FakeTarget();
      await publishTo(
        target,
        profile: _profile(),
        tasks: [_task('a', seconds: 41 * 3600)],
      );
      expect(target.published, hasLength(1));
      expect(target.published.single.handle, 'ada');
      expect(target.published.single.hours, 41);
    });

    test('a published copy that cannot be READ is no copy at all', () async {
      // The bug this pins. Firestore throws on a cache read for a document
      // it does not hold — which is every account that has never published
      // — and treating that as "already up to date" left them unpublished
      // for good: no document, so no read, so no write, so no document.
      final target = _FakeTarget(readThrows: true);
      await publishTo(
        target,
        profile: _profile(),
        tasks: [_task('a', seconds: 41 * 3600)],
      );
      expect(target.published, hasLength(1));
    });

    test('an unchanged figure writes nothing, however often it is asked', () async {
      final tasks = [_task('a', seconds: 41 * 3600 + 59 * 60)];
      final target = _FakeTarget(
        stored: _published(
          hours: 41,
          seconds: 41 * 3600 + 59 * 60,
          ringProgress: ringProgressOf(tasks),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await publishTo(target, profile: _profile(), tasks: tasks);
      }
      expect(target.published, isEmpty);
    });

    test('a changed figure writes once, and then not again', () async {
      final target = _FakeTarget(stored: _published(hours: 41));
      Future<void> go() => publishTo(
        target,
        profile: _profile(),
        tasks: [_task('a', seconds: 42 * 3600)],
      );
      await go();
      await go();
      await go();
      expect(target.published, hasLength(1));
      expect(target.published.single.hours, 42);
    });

    test('a guest with no handle publishes nothing at all', () async {
      final target = _FakeTarget();
      await publishTo(
        target,
        profile: _profile(username: ''),
        tasks: [_task('a', seconds: 41 * 3600)],
      );
      await publishTo(
        target,
        profile: null,
        tasks: [_task('a', seconds: 41 * 3600)],
      );
      expect(target.published, isEmpty);
    });
  });

  group('the ring', () {
    test('fills by the task furthest through its band, as my own does', () {
      // 19h of 20 is nearly there whatever it has logged in total; a task
      // at 81h has just started a band.
      expect(
        ringProgressOf([_task('a', seconds: 19 * 3600)]),
        closeTo(0.95, 0.001),
      );
      expect(
        ringProgressOf([
          _task('a', seconds: 19 * 3600),
          _task('b', seconds: 81 * 3600),
        ]),
        closeTo(0.95, 0.001),
      );
      expect(ringProgressOf(const []), 0);
    });

    test('is rounded to a hundredth — a finer figure is a write nobody sees', () {
      final p = ringProgressOf([_task('a', seconds: 3607)]);
      expect(p, (p * 100).round() / 100);
    });

    test('a task put away is not something you are climbing', () {
      expect(
        ringProgressOf([
          Task(
            id: 'old',
            name: 'old',
            secondsByDay: const {'2026-10-01': 19 * 3600},
            archived: true,
          ),
        ]),
        0,
      );
    });

    test('it is published, and a changed fill is worth a write', () async {
      final target = _FakeTarget();
      await publishTo(
        target,
        profile: _profile(),
        tasks: [_task('a', seconds: 10 * 3600)],
      );
      expect(target.published.single.ringProgress, closeTo(0.5, 0.001));
      expect(target.published.single.toMap()['ringProgress'], isNotNull);

      // The hours have not moved, but the ring has.
      await publishTo(
        target,
        profile: _profile(),
        tasks: [_task('a', seconds: 10 * 3600 + 30 * 60)],
      );
      expect(target.published, hasLength(2));
      expect(target.published.last.hours, 10);
      expect(target.published.last.ringProgress, closeTo(0.53, 0.011));
    });
  });

  group('the friend mirror, live', () {
    test('it is read again when a friendship of mine changes', () async {
      // Before they accept, the read is REFUSED and the refusal is cached
      // as an empty list. The acceptance is exactly the moment nothing was
      // asking again — which is why the count only appeared after a
      // relaunch.
      final friendships = StreamController<List<Friendship>>();
      addTearDown(friendships.close);
      var answer = <String>[];
      var reads = 0;
      final container = ProviderContainer(
        overrides: [
          friendshipsProvider.overrideWith((ref) => friendships.stream),
          friendMirrorReaderProvider.overrideWithValue((uid, source) async {
            reads++;
            return answer;
          }),
        ],
      );
      addTearDown(container.dispose);
      // A listener, because the screen is one: a provider nobody is
      // watching is paused, and a paused provider is not what this is
      // about.
      final sub = container.listen(friendUidsProvider('them'), (_, _) {});
      addTearDown(sub.close);

      friendships.add(const []);
      await Future<void>.delayed(Duration.zero);
      expect(await container.read(friendUidsProvider('them').future), isEmpty);
      final before = reads;

      // They accept: the friendship moves, and the list becomes readable.
      answer = ['a', 'b'];
      friendships.add([_friendship('them')]);
      // The stream's emission, then the rebuild it causes.
      await Future<void>.delayed(Duration.zero);
      await container.pump();

      expect(
        await container.read(friendUidsProvider('them').future),
        ['a', 'b'],
      );
      expect(reads, greaterThan(before), reason: 'nothing asked again');
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

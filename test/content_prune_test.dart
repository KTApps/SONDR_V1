import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/friends/content_prune.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/friendship.dart';

/// Taking someone out of what you have already written.
///
/// A post's audience is frozen when it is written, and so is a comment's.
/// Unfriending used to leave the other person inside every audience they
/// were in, so they kept seeing old posts and old comments; blocking did
/// the same. Both prune now — both, so that posts going quiet cannot be
/// read as the difference between the two.
void main() {
  const me = 'uid_me';
  const them = 'uid_them';
  const other = 'uid_other';

  group('the prune itself', () {
    late _FakeAudiences audiences;
    late _MemoryPending pending;
    late ContentPruner pruner;

    ContentPruner build() => ContentPruner(
          uid: me,
          audiences: audiences,
          pending: pending,
        );

    setUp(() {
      audiences = _FakeAudiences(['posts/p1', 'posts/p2/comments/c1']);
      pending = _MemoryPending();
      pruner = build();
    });

    test('removes the target from every document of mine', () async {
      await pruner.pruneMyContentFor(them);

      expect(audiences.removed['posts/p1'], [them]);
      expect(audiences.removed['posts/p2/comments/c1'], [them]);
    });

    test('nothing is left pending once the server has confirmed', () async {
      await pruner.pruneMyContentFor(them);

      expect(await pending.read(), isEmpty);
    });

    test('the target is recorded BEFORE the work starts', () async {
      audiences.onFirstRemoval = () {
        expect(
          pending.uids,
          contains(them),
          reason: 'a prune that dies here would never be retried',
        );
      };

      await pruner.pruneMyContentFor(them);
      expect(audiences.onFirstRemovalRan, isTrue);
    });

    test('a prune that never reaches the server stays pending', () async {
      audiences.fail = true;

      await expectLater(pruner.pruneMyContentFor(them), throwsA(isA<Object>()));

      expect(await pending.read(), [them]);
    });

    test('a retry at launch finishes it, and clears it', () async {
      audiences.fail = true;
      await expectLater(pruner.pruneMyContentFor(them), throwsA(isA<Object>()));
      audiences.fail = false;

      await build().runPending();

      expect(audiences.removed['posts/p1'], [them]);
      expect(await pending.read(), isEmpty);
    });

    test('a retry with nothing pending does nothing', () async {
      await build().runPending();

      expect(audiences.calls, isEmpty);
    });

    test('a failing retry keeps the entry for the launch after', () async {
      audiences.fail = true;
      await expectLater(pruner.pruneMyContentFor(them), throwsA(isA<Object>()));

      // Must not throw: this runs behind a cold start.
      await build().runPending();

      expect(await pending.read(), [them]);
    });

    test('running it twice is harmless', () async {
      await pruner.pruneMyContentFor(them);
      await pruner.pruneMyContentFor(them);

      expect(
        audiences.removed['posts/p1'],
        [them, them],
        reason: 'arrayRemove of something already gone is a no-op',
      );
      expect(await pending.read(), isEmpty);
    });

    test('pruning yourself is refused', () async {
      await pruner.pruneMyContentFor(me);

      expect(audiences.calls, isEmpty);
      expect(await pending.read(), isEmpty);
    });
  });

  group('batching', () {
    test('never asks for more than Firestore will take in one write',
        () async {
      final audiences = _FakeAudiences([
        for (var i = 0; i < 1001; i++) 'posts/p$i',
      ]);
      final pruner = ContentPruner(
        uid: me,
        audiences: audiences,
        pending: _MemoryPending(),
      );

      await pruner.pruneMyContentFor(them);

      expect(ContentPruner.batchLimit, lessThanOrEqualTo(500));
      expect(audiences.calls.length, 3, reason: '1001 over 450 is three');
      expect(audiences.calls.map((c) => c.length), [450, 450, 101]);
      expect(audiences.removed.length, 1001, reason: 'a document was skipped');
    });

    test('no documents means no writes at all', () async {
      final audiences = _FakeAudiences(const []);
      await ContentPruner(
        uid: me,
        audiences: audiences,
        pending: _MemoryPending(),
      ).pruneMyContentFor(them);

      expect(audiences.calls, isEmpty);
    });
  });

  group('what the repository prunes on', () {
    late FakeFirebaseFirestore db;
    late _RecordingPruner pruner;
    late FriendsRepository repo;

    setUp(() {
      db = FakeFirebaseFirestore();
      pruner = _RecordingPruner();
      repo = FriendsRepository(db: db, uid: me, pruner: pruner);
    });

    test('blocking prunes', () async {
      await repo.blockUser(
        targetUid: them,
        username: 'them',
        displayName: 'Them',
      );
      await pumpEventQueue();

      expect(pruner.pruned, [them]);
    });

    test('unfriending prunes the other half of the pair', () async {
      await repo.remove(Friendship.pairId(me, them));
      await pumpEventQueue();

      expect(pruner.pruned, [them]);
    });

    test('unblocking prunes nothing — nothing is put back either', () async {
      await repo.blockUser(
        targetUid: them,
        username: 'them',
        displayName: 'Them',
      );
      await pumpEventQueue();
      pruner.pruned.clear();

      await repo.unblockUser(them);
      await pumpEventQueue();

      expect(pruner.pruned, isEmpty);
    });

    test('a pair id this user is not in prunes nobody', () async {
      await repo.remove(Friendship.pairId(them, other));
      await pumpEventQueue();

      expect(pruner.pruned, isEmpty);
    });

    test('blocking still records the block and drops the friendship',
        () async {
      await db
          .collection('friendships')
          .doc(Friendship.pairId(me, them))
          .set({'users': [me, them], 'status': 'accepted'});

      await repo.blockUser(
        targetUid: them,
        username: 'them',
        displayName: 'Them',
      );

      final block = await db.collection('blocks').doc('${me}__$them').get();
      expect(block.exists, isTrue);
      expect(block.data()!['blocker'], me);
      final pair =
          await db.collection('friendships').doc(Friendship.pairId(me, them)).get();
      expect(pair.exists, isFalse);
    });
  });

  group('the other half of a pair id', () {
    test('is whichever half is not me', () {
      expect(Friendship.otherIn(Friendship.pairId(me, them), me), them);
      expect(Friendship.otherIn(Friendship.pairId(me, them), them), me);
    });

    test('is null when I am not in it', () {
      expect(Friendship.otherIn(Friendship.pairId(them, other), me), isNull);
    });

    test('is null for something that is not a pair id', () {
      expect(Friendship.otherIn('nonsense', me), isNull);
    });
  });

  group('the real Firestore audiences', () {
    test('finds my posts and my comments, and no one else\'s', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('posts').doc('mine').set({
        'authorUid': me,
        'audience': [me, them],
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
      });
      await db.collection('posts').doc('theirs').set({
        'authorUid': them,
        'audience': [me, them],
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
      });
      await db.collection('posts').doc('theirs').collection('comments').doc('c1').set({
        'authorUid': me,
        'audience': [me, them],
      });
      await db.collection('posts').doc('theirs').collection('comments').doc('c2').set({
        'authorUid': them,
        'audience': [me, them],
      });

      final found = await FirestoreAudiences(db: db, uid: me).mine();

      expect(
        found.toSet(),
        {'posts/mine', 'posts/theirs/comments/c1'},
      );
    });

    /// The query asks for authorUid AND audience, because the posts read
    /// rule grants on audience alone: a query that does not constrain it is
    /// refused outright in production, which is why this prune has been
    /// failing there since it shipped. A post of mine without me in its own
    /// audience cannot exist — and is the one document that proves the
    /// filter is being applied.
    test('the posts query is audience-filtered', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('posts').doc('mine').set({
        'authorUid': me,
        'audience': [me, them],
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
      });
      await db.collection('posts').doc('impossible').set({
        'authorUid': me,
        'audience': [them],
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
      });

      final found = await FirestoreAudiences(db: db, uid: me).mine();

      expect(
        found,
        ['posts/mine'],
        reason: 'the query ran without its audience filter',
      );
    });

    test('removeFrom takes the uid out and leaves the rest', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('posts').doc('mine').set({
        'authorUid': me,
        'audience': [me, them, other],
      });

      await FirestoreAudiences(db: db, uid: me)
          .removeFrom(['posts/mine'], them);

      final after = await db.collection('posts').doc('mine').get();
      expect(after.data()!['audience'], [me, other]);
    });
  });
}

class _FakeAudiences implements PrunableAudiences {
  _FakeAudiences(this.paths);

  final List<String> paths;

  /// Every call to [removeFrom], as the chunk it was given.
  final List<List<String>> calls = [];

  /// Path -> the uids removed from it, in order.
  final Map<String, List<String>> removed = {};

  bool fail = false;
  void Function()? onFirstRemoval;
  bool onFirstRemovalRan = false;

  @override
  Future<List<String>> mine() async => List<String>.from(paths);

  @override
  Future<void> removeFrom(List<String> chunk, String targetUid) async {
    final hook = onFirstRemoval;
    if (hook != null) {
      onFirstRemovalRan = true;
      onFirstRemoval = null;
      hook();
    }
    if (fail) throw StateError('never acknowledged');
    calls.add(List<String>.from(chunk));
    for (final p in chunk) {
      (removed[p] ??= []).add(targetUid);
    }
  }
}

class _MemoryPending implements PendingPrunes {
  final List<String> uids = [];

  @override
  Future<List<String>> read() async => List<String>.from(uids);

  @override
  Future<void> add(String uid) async {
    if (!uids.contains(uid)) uids.add(uid);
  }

  @override
  Future<void> remove(String uid) async => uids.remove(uid);
}

class _RecordingPruner implements ContentPruner {
  final List<String> pruned = [];

  @override
  Future<void> pruneMyContentFor(String targetUid) async => pruned.add(targetUid);

  @override
  Future<void> runPending() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/auth/account_cascade.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/friends/content_prune.dart';

/// The three gaps the production clean-up found, and the shape of the one
/// that caused the drift.
///
/// A like is three documents — the liker's mirror, the copy under the
/// post, the count on the post — and the two deletions that touch them
/// used to take some and leave others. A deleted post left its likes and
/// comments behind it. A deleted account left its name in everyone
/// else's notices.
const me = 'me';
const them = 'them';
const third = 'third';

class _NoFiles implements AccountFiles {
  @override
  Future<List<String>> list(String prefix) async => const [];
  @override
  Future<void> delete(String path) async {}
}

/// Fails the first batch that touches [failOnPath], once, so a run can be
/// interrupted where it matters and then run again.
class _Flaky extends FakeFirebaseFirestore {
  _Flaky(this.failOnPath);

  final String failOnPath;

  /// A dropped connection: the kind of failure a retry is for, and the
  /// kind the cascade must not mistake for "there is nothing to do".
  static const String code = 'unavailable';
  bool armed = true;

  @override
  WriteBatch batch() => _FlakyBatch(super.batch(), this);
}

class _FlakyBatch implements WriteBatch {
  _FlakyBatch(this.inner, this.owner);

  final WriteBatch inner;
  final _Flaky owner;
  final List<String> paths = [];

  @override
  void delete(DocumentReference<Object?> document) {
    paths.add(document.path);
    inner.delete(document);
  }

  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) =>
      inner.set(document, data, options);

  @override
  void update(DocumentReference<Object?> document, Map<Object, Object?> data) {
    paths.add(document.path);
    inner.update(document, data);
  }

  @override
  Future<void> commit() async {
    if (owner.armed && paths.contains(owner.failOnPath)) {
      owner.armed = false;
      throw FirebaseException(plugin: 'cloud_firestore', code: _Flaky.code);
    }
    await inner.commit();
  }
}

AccountCascade cascadeOn(FirebaseFirestore db) => AccountCascade(
  db: db,
  files: _NoFiles(),
  audiences: FirestoreAudiences(db: db, uid: me),
  uid: me,
);

/// A post of [them]'s, with a like of mine on it in whichever shape.
Future<void> seedLike(
  FirebaseFirestore db, {
  required bool withCopyUnderThePost,
  int likeCount = 1,
}) async {
  await db.doc('posts/p1').set({
    'authorUid': them,
    'audience': [me, them],
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
    'likeCount': likeCount,
    'commentCount': 0,
  });
  await db.doc('users/$me/likes/p1').set({'createdAt': 1});
  if (withCopyUnderThePost) {
    await db.doc('posts/p1/likes/$me').set({'at': 1});
  }
}

Future<int> likeCountOf(FirebaseFirestore db, String id) async =>
    ((await db.doc('posts/$id').get()).data()?['likeCount'] as num?)?.toInt() ?? 0;

Future<bool> exists(FirebaseFirestore db, String path) async =>
    (await db.doc(path).get()).exists;

void main() {
  group('a like is three documents, and a deletion takes all three', () {
    test('the shape that caused the drift: counted and mirrored, with no copy under the post', () async {
      final db = FakeFirebaseFirestore();
      // A like made before the post kept its own copy of it — every like
      // between the counter shipping and the copy shipping looks like
      // this, and this is what leaves a count one above the documents.
      await seedLike(db, withCopyUnderThePost: false);
      expect(await likeCountOf(db, 'p1'), 1);
      expect((await db.collection('posts/p1/likes').get()).size, 0,
          reason: 'the drift: one counted, none to count');

      await cascadeOn(db).run();
      // Tolerated, not tripped over: the count comes down, the mirror
      // goes, and the copy that was never there is not missed.
      expect(await likeCountOf(db, 'p1'), 0);
      expect(await exists(db, 'users/$me/likes/p1'), isFalse);
    });

    test('the copy under the post goes with the mirror and the count', () async {
      final db = FakeFirebaseFirestore();
      await seedLike(db, withCopyUnderThePost: true);
      await cascadeOn(db).run();
      expect(await exists(db, 'posts/p1/likes/$me'), isFalse,
          reason: 'the gap: this used to be left behind');
      expect(await exists(db, 'users/$me/likes/p1'), isFalse);
      expect(await likeCountOf(db, 'p1'), 0);
      expect((await db.collection('posts/p1/likes').get()).size, 0);
    });

    test('interrupted, then run again: the count comes off exactly once', () async {
      final db = _Flaky('posts/p1');
      await seedLike(db, withCopyUnderThePost: true);
      // The batch that carries the like fails once. Nothing of it lands.
      await expectLater(cascadeOn(db).run(), throwsA(isA<FirebaseException>()));
      expect(await likeCountOf(db, 'p1'), 1, reason: 'all or none');
      expect(await exists(db, 'users/$me/likes/p1'), isTrue,
          reason: 'the mirror is the marker a retry starts from');

      await cascadeOn(db).run();
      expect(await likeCountOf(db, 'p1'), 0);
      expect(await exists(db, 'posts/p1/likes/$me'), isFalse);

      // And a third run, over a job already done, changes nothing.
      await cascadeOn(db).run();
      expect(await likeCountOf(db, 'p1'), 0, reason: 'never twice');
    });

    test('a post that has gone is not a failure, and takes no count with it', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('users/$me/likes/vanished').set({'createdAt': 1});
      await cascadeOn(db).run();
      expect(await exists(db, 'users/$me/likes/vanished'), isFalse);
    });
  });

  group('the notices an account left in other people\'s inboxes', () {
    Future<FakeFirebaseFirestore> seedNotices([FakeFirebaseFirestore? on]) async {
      final db = on ?? FakeFirebaseFirestore();
      // Two I caused, in two different inboxes.
      await db.doc('notifications/$them/items/n1')
          .set({'type': 'like', 'actorUid': me, 'actorHandle': 'ada', 'postId': 'p1'});
      await db.doc('notifications/$third/items/n2')
          .set({'type': 'milestone', 'actorUid': me, 'actorHandle': 'ada', 'postId': 'p2'});
      // One somebody else caused, in a third person's inbox.
      await db.doc('notifications/$third/items/n3')
          .set({'type': 'like', 'actorUid': them, 'actorHandle': 'cass', 'postId': 'p3'});
      // And my own inbox.
      await db.doc('notifications/$me/items/n4')
          .set({'type': 'like', 'actorUid': them, 'actorHandle': 'cass', 'postId': 'p4'});
      return db;
    }

    test('go, wherever they landed; everyone else\'s stay', () async {
      final db = await seedNotices();
      await cascadeOn(db).run();
      expect(await exists(db, 'notifications/$them/items/n1'), isFalse);
      expect(await exists(db, 'notifications/$third/items/n2'), isFalse);
      expect(await exists(db, 'notifications/$third/items/n3'), isTrue,
          reason: 'not theirs to take');
      expect(await exists(db, 'notifications/$me/items/n4'), isFalse,
          reason: 'their own inbox goes too');
    });

    test('running again over the same job takes nothing more', () async {
      final db = await seedNotices();
      await cascadeOn(db).run();
      await cascadeOn(db).run();
      expect(await exists(db, 'notifications/$third/items/n3'), isTrue);
    });
  });

  group('a deleted post takes what is under it', () {
    Future<void> seedPost(FirebaseFirestore db) async {
      await db.doc('posts/p1').set({
        'authorUid': me,
        'audience': [me, them, third],
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
        'likeCount': 2,
        'commentCount': 2,
        // No storage path, so nothing reaches for a bucket in a test.
        'photos': [
          {'url': 'u', 'storagePath': ''},
        ],
      });
      await db.doc('posts/p1/likes/$them').set({'at': 1});
      await db.doc('posts/p1/likes/$third').set({'at': 2});
      await db.doc('users/$them/likes/p1').set({'createdAt': 1});
      await db.doc('users/$third/likes/p1').set({'createdAt': 2});
      await db.doc('posts/p1/comments/c1')
          .set({'authorUid': them, 'audience': [me, them], 'text': 'a'});
      await db.doc('posts/p1/comments/c2')
          .set({'authorUid': third, 'audience': [me, them], 'text': 'r', 'parentId': 'c1'});
      // Another post, untouched by any of it.
      await db.doc('posts/p2').set({
        'authorUid': them, 'audience': [me, them], 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
        'likeCount': 1, 'commentCount': 0,
      });
      await db.doc('posts/p2/likes/$them').set({'at': 1});
      await db.doc('users/$them/likes/p2').set({'createdAt': 1});
    }

    Post postP1() => MilestonePost(
      id: 'p1',
      authorUid: me,
      author: const PostAuthor(username: 'ada', displayName: 'Ada'),
      createdAt: DateTime(2026, 10, 1),
      caption: null,
      photos: const [PostPhoto(url: 'u', storagePath: '')],
      taskName: 'Spanish',
      milestoneHours: 20,
      totalHours: 20,
    );

    test('its likes, its comments, its replies, and each liker\'s mirror', () async {
      final db = FakeFirebaseFirestore();
      await seedPost(db);
      await PostsRepository(db: db, uid: me).deletePost(postP1());

      expect(await exists(db, 'posts/p1'), isFalse);
      expect((await db.collection('posts/p1/likes').get()).size, 0);
      expect((await db.collection('posts/p1/comments').get()).size, 0,
          reason: 'the reply goes with the comment: one collection, one sweep');
      expect(await exists(db, 'users/$them/likes/p1'), isFalse);
      expect(await exists(db, 'users/$third/likes/p1'), isFalse);
      // Nothing of the other post, or of anyone's other likes.
      expect(await exists(db, 'posts/p2'), isTrue);
      expect(await exists(db, 'posts/p2/likes/$them'), isTrue);
      expect(await exists(db, 'users/$them/likes/p2'), isTrue);
    });

    test('interrupted, then run again: the post is still there to finish from, and then nothing is', () async {
      final db = _Flaky('posts/p1/comments/c1');
      await seedPost(db);
      final repo = PostsRepository(db: db, uid: me);
      await expectLater(repo.deletePost(postP1()), throwsA(isA<FirebaseException>()));
      // The post outlives its own contents, which is what lets a second
      // run reach them: every rule for what is under it is proved by it.
      expect(await exists(db, 'posts/p1'), isTrue);
      expect((await db.collection('posts/p1/comments').get()).size, 2,
          reason: 'the comments batch was all or none');

      await repo.deletePost(postP1());
      expect(await exists(db, 'posts/p1'), isFalse);
      expect((await db.collection('posts/p1/likes').get()).size, 0);
      expect((await db.collection('posts/p1/comments').get()).size, 0);
      expect(await exists(db, 'users/$them/likes/p1'), isFalse);
    });

    test('a post with nothing under it deletes cleanly, and again', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('posts/p1').set({
        'authorUid': me, 'audience': [me], 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
        'likeCount': 0, 'commentCount': 0, 'photos': [],
      });
      final repo = PostsRepository(db: db, uid: me);
      await repo.deletePost(postP1());
      await repo.deletePost(postP1());
      expect(await exists(db, 'posts/p1'), isFalse);
    });

    test('the cascade takes its own posts the same way', () async {
      final db = FakeFirebaseFirestore();
      await seedPost(db);
      await cascadeOn(db).run();
      expect(await exists(db, 'posts/p1'), isFalse);
      expect((await db.collection('posts/p1/likes').get()).size, 0);
      expect((await db.collection('posts/p1/comments').get()).size, 0);
      expect(await exists(db, 'users/$them/likes/p1'), isFalse,
          reason: 'their mirror of a like on a post that no longer exists');
      expect(await exists(db, 'users/$them/likes/p2'), isTrue);
    });
  });
}

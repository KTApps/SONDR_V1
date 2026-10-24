import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/auth/account_cascade.dart';
import 'package:sondr/features/friends/content_prune.dart';

/// Deleting an account, and what it must leave alone.
///
/// Two users: `me`, who is leaving, and `them`, who is not. They are
/// friends, they have both posted, they have commented on each other's
/// posts, they have liked each other's posts, and each has blocked the
/// other. Afterwards nothing of `me` may remain except the two leftovers
/// that are somebody else's property, and everything of `them` must be
/// exactly as it was.
const me = 'me';
const them = 'them';

class _Files implements AccountFiles {
  _Files(this.objects, {this.listThrows = false});

  final List<String> objects;
  final bool listThrows;
  final List<String> deleted = [];
  final List<String> listed = [];

  @override
  Future<List<String>> list(String prefix) async {
    listed.add(prefix);
    if (listThrows) {
      throw FirebaseException(plugin: 'storage', code: 'unauthorized');
    }
    return [for (final o in objects) if (o.startsWith('$prefix/')) o];
  }

  @override
  Future<void> delete(String path) async {
    if (!objects.remove(path)) {
      throw FirebaseException(plugin: 'storage', code: 'object-not-found');
    }
    deleted.add(path);
  }
}

/// Fails the Nth write, once, so a half-finished cascade can be retried.
class _Flaky extends FakeFirebaseFirestore {
  _Flaky(this.failOnPath);

  final String failOnPath;
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
  void update(
    DocumentReference<Object?> document,
    Map<Object, Object?> data,
  ) {
    paths.add(document.path);
    inner.update(document, data);
  }

  @override
  Future<void> commit() async {
    if (owner.armed && paths.contains(owner.failOnPath)) {
      owner.armed = false;
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    await inner.commit();
  }
}

Future<void> seed(FirebaseFirestore db) async {
  // My space, every subcollection of it.
  await db.doc('users/$me/meta/profile').set({'username': 'ada'});
  await db.doc('users/$me/meta/habitList').set({'habits': []});
  await db.doc('users/$me/tasks/t1').set({'name': 'Golf'});
  await db.doc('users/$me/habitDays/2026-10-01').set({'done': true});
  await db.doc('users/$me/photos/ph1').set({
    'storagePath': 'users/$me/photos/ph1.jpg',
  });
  await db.doc('users/$me/collages/c1').set({'photoIds': ['ph1']});
  await db.doc('users/$me/hidden/post__x').set({'hiddenAt': 1});
  // A like of mine on THEIR post, and one on my own.
  await db.doc('users/$me/likes/theirs').set({'createdAt': 1});
  await db.doc('users/$me/likes/mine').set({'createdAt': 1});

  // Their space, which must survive untouched.
  await db.doc('users/$them/meta/profile').set({'username': 'cass'});
  await db.doc('users/$them/tasks/t9').set({'name': 'Run'});
  await db.doc('users/$them/likes/mine').set({'createdAt': 1});

  await db.doc('usernames/ada').set({'uid': me});
  await db.doc('usernames/cass').set({'uid': them});

  await db.doc('publicProfiles/$me').set({'handle': 'ada', 'hours': 3});
  await db.doc('publicProfiles/$them').set({'handle': 'cass', 'hours': 9});
  await db.doc('publicProfiles/$me/friends/$them').set({'since': 1});
  await db.doc('publicProfiles/$them/friends/$me').set({'since': 1});

  await db.doc('friendships/${me}__$them').set({
    'users': [me, them],
    'requestedBy': me,
    'status': 'accepted',
  });

  await db.doc('blocks/${me}__other').set({'blocker': me, 'blocked': 'other'});
  // Who invited them, and somebody else's invite naming them — the second
  // is the other person's document and stays.
  await db.doc('invites/$me').set({
    'invitedBy': them,
    'invitedByHandle': 'cass',
    'at': Timestamp.fromDate(DateTime(2026, 9, 1)),
  });
  await db.doc('invites/$them').set({
    'invitedBy': me,
    'invitedByHandle': 'ada',
    'at': Timestamp.fromDate(DateTime(2026, 9, 2)),
  });
  await db.doc('blocks/${them}__$me').set({'blocker': them, 'blocked': me});

  // My post, with a photo, liked by them and commented on by both of us.
  await db.doc('posts/mine').set({
    'authorUid': me,
    'audience': [me, them],
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
    'photos': [
      {'url': 'u', 'storagePath': 'users/$me/posts/mine.jpg'},
    ],
    'likeCount': 1,
    'commentCount': 2,
  });
  await db.doc('posts/mine/comments/by-me').set({
    'authorUid': me,
    'audience': [me, them],
    'text': 'mine',
  });
  await db.doc('posts/mine/comments/by-them').set({
    'authorUid': them,
    'audience': [me, them],
    'text': 'theirs',
  });

  // Their post, which I liked and commented on twice.
  await db.doc('posts/theirs').set({
    'authorUid': them,
    'audience': [me, them],
    'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
    'photos': [
      {'url': 'u', 'storagePath': 'users/$them/posts/theirs.jpg'},
    ],
    'likeCount': 1,
    'commentCount': 2,
  });
  await db.doc('posts/theirs/comments/by-me-1').set({
    'authorUid': me,
    'audience': [me, them],
    'text': 'a',
  });
  await db.doc('posts/theirs/comments/by-me-2').set({
    'authorUid': me,
    'audience': [me, them],
    'text': 'b',
  });
}

void main() {
  late FakeFirebaseFirestore db;
  late _Files files;
  late AccountCascade cascade;

  AccountCascade cascadeOn(FirebaseFirestore on, _Files with_) => AccountCascade(
    db: on,
    files: with_,
    audiences: FirestoreAudiences(db: on, uid: me),
    uid: me,
  );

  _Files myFiles() => _Files([
    'users/$me/photos/ph1.jpg',
    'users/$me/posts/mine.jpg',
    // An upload whose document never landed — only a listing finds this.
    'users/$me/posts/orphan.jpg',
    'users/$them/photos/theirs.jpg',
  ]);

  setUp(() async {
    db = FakeFirebaseFirestore();
    await seed(db);
    files = myFiles();
    cascade = cascadeOn(db, files);
  });

  /// Every path the fixture wrote, by whose it is. Checked one by one
  /// rather than walked: Firestore does not return a document that holds
  /// only subcollections, so a walk silently misses both `users/{uid}` and
  /// anything under a parent that has been deleted — which is exactly where
  /// a leftover would hide.
  const minePaths = [
    'users/$me/meta/profile',
    'users/$me/meta/habitList',
    'users/$me/tasks/t1',
    'users/$me/habitDays/2026-10-01',
    'users/$me/photos/ph1',
    'users/$me/collages/c1',
    'users/$me/hidden/post__x',
    'users/$me/likes/theirs',
    'users/$me/likes/mine',
    'usernames/ada',
    'publicProfiles/$me',
    'publicProfiles/$me/friends/$them',
    'publicProfiles/$them/friends/$me',
    'friendships/${me}__$them',
    'blocks/${me}__other',
    'invites/$me',
    'posts/mine',
    'posts/mine/comments/by-me',
    'posts/theirs/comments/by-me-1',
    'posts/theirs/comments/by-me-2',
  ];

  const theirPaths = [
    'users/$them/meta/profile',
    'users/$them/tasks/t9',
    'users/$them/likes/mine',
    'usernames/cass',
    'publicProfiles/$them',
    'posts/theirs',
    // Their own invite, which happens to name the leaving account: their
    // document, their record of how they arrived.
    'invites/$them',
    // The two leftovers, both of them somebody else's document.
    'blocks/${them}__$me',
    'posts/mine/comments/by-them',
  ];

  Future<List<String>> surviving(
    FirebaseFirestore on,
    List<String> candidates,
  ) async {
    final left = <String>[];
    for (final path in candidates) {
      if ((await on.doc(path).get()).exists) left.add(path);
    }
    return left;
  }

  group('what is left of a deleted account', () {
    test('nothing of theirs is left', () async {
      // Everything is there to start with, or the test proves nothing.
      expect(await surviving(db, minePaths), minePaths);
      await cascade.run();
      expect(await surviving(db, minePaths), isEmpty);
    });

    test('and the two leftovers are left, on purpose', () async {
      await cascade.run();
      // 1. A block THEY placed: their document, and letting a departing
      //    account delete it would let anyone clear themselves off
      //    somebody else's list.
      expect((await db.doc('blocks/${them}__$me').get()).exists, isTrue);
      // 2. Their uid in an audience frozen at write time.
      expect(
        (await db.doc('posts/theirs').get()).data()!['audience'],
        contains(me),
      );
    });

    test('their side is exactly as it was', () async {
      expect(await surviving(db, theirPaths), theirPaths);
      await cascade.run();
      expect(await surviving(db, theirPaths), theirPaths);
      // Their post kept its photo, and its counters came down by exactly
      // what I was holding up: one like, two comments.
      final theirs = (await db.doc('posts/theirs').get()).data()!;
      expect(theirs['likeCount'], 0);
      expect(theirs['commentCount'], 0);
      expect(
        (theirs['photos'] as List).first,
        {'url': 'u', 'storagePath': 'users/$them/posts/theirs.jpg'},
      );
    });

    test('every subcollection of their own space went', () async {
      await cascade.run();
      for (final name in kUserSubcollections) {
        final snap = await db.collection('users/$me/$name').get();
        expect(snap.docs, isEmpty, reason: name);
      }
      expect((await db.doc('users/$me').get()).exists, isFalse);
    });

    /// The query that finds their posts asks for BOTH authorUid and
    /// audience, because the read rule grants on audience alone and a query
    /// that does not constrain it is refused outright in production — which
    /// is what made every deletion fail on the device.
    ///
    /// Nothing can be missed by that filter: every version of the create
    /// path has seeded the audience with the author's own uid. A post
    /// without its own author in the audience cannot exist, and this is
    /// what proves the filter is being applied — it is the one document
    /// the cascade will walk past.
    test('the authored-posts query is audience-filtered', () async {
      await db.doc('posts/impossible').set({
        'authorUid': me,
        'audience': [them],
        'createdAt': Timestamp.fromDate(DateTime(2026, 10, 3)),
        'likeCount': 0,
        'commentCount': 0,
      });
      await cascade.run();
      expect(
        (await db.doc('posts/impossible').get()).exists,
        isTrue,
        reason: 'the query ran without its audience filter',
      );
      // And the real ones still went.
      expect((await db.doc('posts/mine').get()).exists, isFalse);
    });

    test('the handle is free for somebody else', () async {
      await cascade.run();
      expect((await db.doc('usernames/ada').get()).exists, isFalse);
      // And theirs is untouched.
      expect((await db.doc('usernames/cass').get()).data(), {'uid': them});
    });

    test('both halves of the friend mirror, and the friendship', () async {
      await cascade.run();
      expect(
        (await db.doc('publicProfiles/$me/friends/$them').get()).exists,
        isFalse,
      );
      expect(
        (await db.doc('publicProfiles/$them/friends/$me').get()).exists,
        isFalse,
        reason: 'the friend was left with a one-sided entry',
      );
      expect((await db.doc('friendships/${me}__$them').get()).exists, isFalse);
    });

    test('their files, including one Firestore never knew about', () async {
      await cascade.run();
      expect(files.deleted, containsAll(['users/$me/photos/ph1.jpg']));
      expect(files.objects, ['users/$them/photos/theirs.jpg']);
      expect(files.listed, ['users/$me/photos', 'users/$me/posts']);
    });

    test('a refused listing still takes the recorded files', () async {
      final blind = _Files(myFiles().objects, listThrows: true);
      await cascadeOn(db, blind).run();
      // Everything Firestore named is gone; only the orphan nothing refers
      // to is left, because no listing could find it.
      expect(blind.objects, [
        'users/$me/posts/orphan.jpg',
        'users/$them/photos/theirs.jpg',
      ]);
      expect((await db.doc('users/$me').get()).exists, isFalse);
    });
  });

  group('a cascade that is interrupted', () {
    test('a retry finishes the job', () async {
      final flaky = _Flaky('users/$me/tasks/t1');
      await seed(flaky);
      final flakyFiles = myFiles();
      final first = cascadeOn(flaky, flakyFiles);

      await expectLater(first.run(), throwsA(isA<FirebaseException>()));
      // It got as far as the user space, so the steps before it are done
      // and the one it died on is not.
      expect((await flaky.doc('posts/mine').get()).exists, isFalse);
      expect((await flaky.doc('users/$me/tasks/t1').get()).exists, isTrue);
      expect(await surviving(flaky, minePaths), isNotEmpty);

      // Run it again: everything already gone stays gone, and what was
      // left finishes.
      await cascadeOn(flaky, flakyFiles).run();
      expect(await surviving(flaky, minePaths), isEmpty);
      expect(await surviving(flaky, theirPaths), theirPaths);
      // And the counters moved ONCE, not twice.
      final theirs = (await flaky.doc('posts/theirs').get()).data()!;
      expect(theirs['likeCount'], 0);
      expect(theirs['commentCount'], 0);
    });

    test('a second run on a finished account changes nothing', () async {
      await cascade.run();
      await cascadeOn(db, files).run();
      expect(await surviving(db, minePaths), isEmpty);
      expect(await surviving(db, theirPaths), theirPaths);
      final theirs = (await db.doc('posts/theirs').get()).data()!;
      expect(theirs['likeCount'], 0, reason: 'the counter moved twice');
      expect(theirs['commentCount'], 0, reason: 'the counter moved twice');
    });
  });

  group('the subcollection list', () {
    /// The list is the contract — a client cannot ask Firestore what a
    /// document's subcollections are. So this reads the source for every
    /// `users/{uid}/<name>` path the app writes and fails if one of them is
    /// missing from [kUserSubcollections].
    test('names every subcollection the app actually writes', () {
      final found = <String>{};
      final pattern = RegExp(
        r"collection\('users'\)\s*(?://[^\n]*\n\s*)?\.?\s*\n?\s*\.doc\([^)]*\)\s*\n?\s*\.collection\('(\w+)'\)",
        multiLine: true,
      );
      for (final file in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final text = file.readAsStringSync().replaceAll(RegExp(r'\s+'), ' ');
        for (final match in pattern.allMatches(text)) {
          found.add(match.group(1)!);
        }
      }
      expect(found, isNotEmpty, reason: 'the scan found nothing to check');
      expect(
        found.difference(kUserSubcollections.toSet()),
        isEmpty,
        reason: 'kUserSubcollections is missing one: $found',
      );
    });
  });
}

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/posts_repository.dart';

/// A comment carries its own audience.
///
/// The post's is frozen at post time and only its author can prune it — and
/// the commenter is not that author. So the comment takes a copy at
/// creation, which its own author can narrow later.
///
/// The query has to carry the matching filter. Rules are not filters: the
/// read rule requires the reader to be in the comment's audience, and a
/// query that does not constrain that fails WHOLESALE rather than omitting
/// rows. The rules side is proved against the emulator in
/// test/rules/rules.test.mjs; this is the client's half of the contract.
void main() {
  const me = 'uid_me';
  const them = 'uid_them';
  const third = 'uid_third';

  late FakeFirebaseFirestore db;
  late PostsRepository repo;

  Future<void> seedPost(String id, List<String> audience) async {
    await db.collection('posts').doc(id).set({
      'authorUid': third,
      'audience': audience,
      'createdAt': 1,
      'commentCount': 0,
    });
  }

  Future<Map<String, dynamic>> onlyComment(String postId) async {
    final snap =
        await db.collection('posts').doc(postId).collection('comments').get();
    return snap.docs.single.data();
  }

  setUp(() async {
    db = FakeFirebaseFirestore();
    await db
        .collection('users')
        .doc(me)
        .collection('meta')
        .doc('profile')
        .set({'username': 'me', 'displayName': 'Me'});
    repo = PostsRepository(db: db, uid: me);
  });

  test('a new comment copies the post audience, exactly', () async {
    await seedPost('p1', [me, them, third]);

    await repo.addComment('p1', 'hello');

    expect(await onlyComment('p1'), containsPair('audience', [me, them, third]));
  });

  test('the copy follows the post, not the commenter', () async {
    // A post whose audience does not include everyone the commenter knows.
    await seedPost('p1', [me, third]);

    await repo.addComment('p1', 'hello');

    expect(
      (await onlyComment('p1'))['audience'],
      [me, third],
      reason: 'a comment must not reach past the post it is on',
    );
  });

  test('a post with no audience yields an empty one, not a crash', () async {
    await db.collection('posts').doc('p1').set({'authorUid': third});

    await repo.addComment('p1', 'hello');

    expect((await onlyComment('p1'))['audience'], isEmpty);
  });

  test('the comment still carries author, text and a timestamp', () async {
    await seedPost('p1', [me, third]);

    await repo.addComment('p1', '  hello  ');

    final c = await onlyComment('p1');
    expect(c['authorUid'], me);
    expect(c['text'], 'hello');
    expect(c['author'], {'username': 'me', 'displayName': 'Me'});
    expect(c.containsKey('createdAt'), isTrue);
  });

  test('the thread shows comments this reader is in', () async {
    await seedPost('p1', [me, them, third]);
    await repo.addComment('p1', 'mine');

    final list = await repo.watchComments('p1').first;

    expect(list.single.text, 'mine');
  });

  test('a reader pruned from a comment does not see it', () async {
    await seedPost('p1', [me, them, third]);
    await db.collection('posts').doc('p1').collection('comments').doc('c1').set({
      'authorUid': third,
      'author': {'username': 't', 'displayName': 'T'},
      'text': 'pruned',
      // me is deliberately absent.
      'audience': [third, them],
      'createdAt': 1,
    });
    await db.collection('posts').doc('p1').collection('comments').doc('c2').set({
      'authorUid': third,
      'author': {'username': 't', 'displayName': 'T'},
      'text': 'kept',
      'audience': [third, them, me],
      'createdAt': 2,
    });

    final list = await repo.watchComments('p1').first;

    expect(list.map((c) => c.text), ['kept']);
  });

  group('the post audience the comment copies', () {
    // Nothing covered this until now: deleting the audience from post
    // creation passed the whole suite. Everything here rests on it.
    test('is the author\'s accepted friends, plus self', () async {
      await db.collection('friendships').doc('a').set({
        'users': [me, them],
        'status': 'accepted',
      });
      await db.collection('friendships').doc('b').set({
        'users': [me, third],
        'status': 'pending',
      });

      final id = await repo.createSessionPost(taskName: 'Spanish', sessionSeconds: 60);

      final post = await db.collection('posts').doc(id).get();
      expect(
        (post.data()!['audience'] as List).toSet(),
        {me, them},
        reason: 'a pending request is not an audience',
      );
    });

    test('is just me when I have no friends', () async {
      final id = await repo.createSessionPost(taskName: 'Spanish', sessionSeconds: 60);

      final post = await db.collection('posts').doc(id).get();
      expect(post.data()!['audience'], [me]);
    });
  });

  test('a comment with no audience is invisible — the backfill matters',
      () async {
    await seedPost('p1', [me, third]);
    await db.collection('posts').doc('p1').collection('comments').doc('old').set({
      'authorUid': third,
      'author': {'username': 't', 'displayName': 'T'},
      'text': 'written before the field existed',
      'createdAt': 1,
    });

    final list = await repo.watchComments('p1').first;

    expect(
      list,
      isEmpty,
      reason: 'existing comments must be backfilled before this ships',
    );
  });
}

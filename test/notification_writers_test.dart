import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/friends/audience_widen.dart';
import 'package:sondr/features/friends/content_prune.dart';
import 'package:sondr/features/friends/friends_repository.dart';
import 'package:sondr/features/friends/models/friendship.dart';
import 'package:sondr/features/notifications/notifications_repository.dart';

/// Every action that should tell someone, tells them — and never you.
void main() {
  late FakeFirebaseFirestore db;
  late _Recording notes;

  setUp(() async {
    db = FakeFirebaseFirestore();
    notes = _Recording();
    await db.collection('users').doc('me').collection('meta').doc('profile')
        .set({'username': 'ada', 'displayName': 'Ada'});
  });

  group('posts', () {
    PostsRepository repo() => PostsRepository(db: db, uid: 'me', notifier: notes);

    test('a like tells the author', () async {
      await db.collection('posts').doc('p1').set({'authorUid': 'cass', 'audience': ['me', 'cass'], 'likeCount': 0});
      await repo().setLike('p1', true, authorUid: 'cass');
      expect(notes.sent, [('cass', NotificationType.like, 'p1', null)]);
    });

    test('an unlike tells nobody', () async {
      await db.collection('posts').doc('p1').set({'authorUid': 'cass', 'audience': ['me', 'cass'], 'likeCount': 1});
      await repo().setLike('p1', false, authorUid: 'cass');
      expect(notes.sent, isEmpty);
    });

    test('a comment tells the post\'s author', () async {
      await db.collection('posts').doc('p1').set({'authorUid': 'cass', 'audience': ['me', 'cass'], 'commentCount': 0});
      await repo().addComment('p1', 'hi');
      expect(notes.sent.single.$1, 'cass');
      expect(notes.sent.single.$2, NotificationType.comment);
      expect(notes.sent.single.$4, isNotNull, reason: 'the comment id rides along');
    });

    test('a reply tells the parent\'s author, and the post\'s author too', () async {
      await db.collection('posts').doc('p1').set({'authorUid': 'cass', 'audience': ['me', 'cass', 'bea'], 'commentCount': 1});
      await db.collection('posts').doc('p1').collection('comments').doc('top')
          .set({'authorUid': 'bea', 'text': 't', 'audience': ['me', 'cass', 'bea']});
      await repo().addComment('p1', 'yes', parentId: 'top');
      expect(notes.sent.map((s) => (s.$1, s.$2)), [
        ('bea', NotificationType.reply),
        ('cass', NotificationType.comment),
      ]);
      final written = await db.collection('posts').doc('p1').collection('comments').get();
      final reply = written.docs.where((d) => d.id != 'top').single;
      expect(reply.data()['parentId'], 'top');
    });

    test('a reply on your own comment under your own post tells no one', () async {
      await db.collection('posts').doc('p1').set({'authorUid': 'me', 'audience': ['me'], 'commentCount': 1});
      await db.collection('posts').doc('p1').collection('comments').doc('top')
          .set({'authorUid': 'me', 'text': 't', 'audience': ['me']});
      await repo().addComment('p1', 'me again', parentId: 'top');
      expect(notes.sent, isEmpty);
    });

    test('deleting a comment takes its replies, and the count moves by all of them', () async {
      final post = db.collection('posts').doc('p1');
      await post.set({'authorUid': 'cass', 'audience': ['me', 'cass'], 'commentCount': 3});
      await post.collection('comments').doc('top').set({'authorUid': 'me', 'text': 't'});
      await post.collection('comments').doc('r1').set({'authorUid': 'bea', 'text': 'r', 'parentId': 'top'});
      await post.collection('comments').doc('r2').set({'authorUid': 'cass', 'text': 'r', 'parentId': 'top'});
      await post.collection('comments').doc('other').set({'authorUid': 'bea', 'text': 'o'});
      await repo().deleteComment('p1', 'top');
      final left = await post.collection('comments').get();
      expect(left.docs.map((d) => d.id), ['other']);
      expect((await post.get()).data()?['commentCount'], 0);
    });

    test('a milestone tells every friend it reaches, not me', () async {
      await db.collection('friendships').doc(Friendship.pairId('me', 'cass'))
          .set({'users': ['cass', 'me'], 'status': 'accepted'});
      await db.collection('friendships').doc(Friendship.pairId('me', 'bea'))
          .set({'users': ['bea', 'me'], 'status': 'accepted'});
      await repo().createMilestonePost(taskName: 'Spanish', milestoneHours: 20, totalHours: 21);
      expect(notes.sent.map((s) => s.$1).toSet(), {'cass', 'bea'});
      expect(notes.sent.every((s) => s.$2 == NotificationType.milestone), isTrue);
      expect(notes.milestones.toSet(), {('Spanish', 20)});
    });
  });

  group('friends', () {
    FriendsRepository repo() => FriendsRepository(
      db: db,
      uid: 'me',
      pruner: _NoPrune(),
      widener: AudienceWidener(uid: 'me', audiences: _NoAudiences(), blocked: () async => const {}),
      notifier: notes,
    );

    test('a request tells the person asked', () async {
      await db.collection('usernames').doc('cass').set({'uid': 'cass'});
      await repo().sendRequest('cass');
      expect(notes.sent, [('cass', NotificationType.request, null, null)]);
    });

    test('an acceptance tells the one who asked', () async {
      await db.collection('friendships').doc(Friendship.pairId('me', 'cass')).set({
        'users': ['cass', 'me'], 'requestedBy': 'cass', 'status': 'pending',
        'profiles': {'cass': {'username': 'cass', 'displayName': 'Cass'}},
      });
      await repo().accept(Friendship.pairId('me', 'cass'));
      expect(notes.sent, [('cass', NotificationType.accepted, null, null)]);
    });

    test('arriving from an invite tells the one who invited', () async {
      await repo().recordInvite(inviterUid: 'cass', inviterHandle: 'cass');
      expect(notes.sent.map((s) => (s.$1, s.$2)), [('cass', NotificationType.invite)]);
    });
  });

  test('the real writer says nothing to yourself, and shapes the document exactly', () {
    final writer = FirestoreNotificationsWriter(db: db, uid: 'me');
    final batch = db.batch();
    writer.add(batch, recipientUid: 'me', type: NotificationType.like, actorHandle: 'ada', postId: 'p');
    writer.add(batch, recipientUid: '', type: NotificationType.like, actorHandle: 'ada', postId: 'p');
    final doc = FirestoreNotificationsWriter.document(
      type: NotificationType.milestone, actorUid: 'me', actorHandle: 'ada',
      postId: 'p', taskName: 'Spanish', hours: 20,
    );
    expect(doc.keys.toSet(), {'type', 'actorUid', 'actorHandle', 'at', 'postId', 'taskName', 'hours'});
    expect(doc['at'], isA<FieldValue>());
    final like = FirestoreNotificationsWriter.document(
      type: NotificationType.like, actorUid: 'me', actorHandle: 'ada', postId: 'p',
    );
    expect(like.keys.toSet(), {'type', 'actorUid', 'actorHandle', 'at', 'postId'});
  });
}

class _Recording implements NotificationsWriter {
  final List<(String, NotificationType, String?, String?)> sent = [];
  final List<(String?, int?)> milestones = [];

  @override
  void add(
    WriteBatch batch, {
    required String recipientUid,
    required NotificationType type,
    required String actorHandle,
    String? postId,
    String? commentId,
    String? taskName,
    int? hours,
    String? id,
  }) {
    if (recipientUid.isEmpty || recipientUid == 'me') return;
    sent.add((recipientUid, type, postId, commentId));
    if (type == NotificationType.milestone) milestones.add((taskName, hours));
  }
}

class _NoPrune implements ContentPruner {
  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}

class _NoAudiences implements WidenableAudiences {
  @override
  dynamic noSuchMethod(Invocation invocation) async => const [];
}

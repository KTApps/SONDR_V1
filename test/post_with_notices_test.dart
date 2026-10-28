import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/firebase_share_backend.dart';
import 'package:sondr/features/notifications/notifications_repository.dart';

/// The post and its friends' notices, written together: the post and the
/// first batch's worth of notices in one batch, the rest after — so a
/// post that is there has told its friends.
void main() {
  Future<({FakeFirebaseFirestore db, int notices})> write(int friendCount) async {
    final db = FakeFirebaseFirestore();
    final friends = [for (var i = 0; i < friendCount; i++) 'f$i'];
    await writePostWithNotices(
      db: db,
      notifier: FirestoreNotificationsWriter(db: db, uid: 'me'),
      postId: 'p1',
      doc: {'authorUid': 'me', 'audience': ['me', ...friends], 'type': 'milestone'},
      friends: friends,
      actorHandle: 'cass',
      taskName: 'Spanish',
      hours: 20,
      landed: () async => false,
    );
    var notices = 0;
    for (final u in friends) {
      final n = await db.collection('notifications').doc(u).collection('items').doc('p1').get();
      if (n.exists) notices++;
    }
    return (db: db, notices: notices);
  }

  test('the post lands, and a notice under the post\'s id for every friend', () async {
    final r = await write(3);
    final post = await r.db.collection('posts').doc('p1').get();
    expect(post.exists, isTrue);
    expect(post.data()!['type'], 'milestone');
    expect(r.notices, 3);
    final n = await r.db.collection('notifications').doc('f0').collection('items').doc('p1').get();
    expect(n.data()!['type'], 'milestone');
    expect(n.data()!['actorHandle'], 'cass');
    expect(n.data()!['postId'], 'p1');
    expect(n.data()!['hours'], 20);
  });

  test('more friends than one batch carries: every one is told, in batches after the post\'s', () async {
    final r = await write(kPostBatchSize * 2 + 7);
    expect(r.notices, kPostBatchSize * 2 + 7);
    expect((await r.db.collection('posts').doc('p1').get()).exists, isTrue);
  });

  test('no friends: the post alone', () async {
    final r = await write(0);
    expect(r.notices, 0);
    expect((await r.db.collection('posts').doc('p1').get()).exists, isTrue);
  });

  test('the first batch holds the post and at most the batch\'s worth less one', () {
    expect(kPostBatchSize, 450);
  });
}

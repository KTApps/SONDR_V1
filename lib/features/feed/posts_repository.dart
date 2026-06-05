import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import 'models/post.dart';

/// Reads the friends-only feed and creates posts. Posts live in a top-level
/// `posts` collection; each carries an `audience` array (the author's accepted
/// friends at post time + self) so the feed is a single array-contains query and
/// the read rule needs no per-post friendship lookup.
class PostsRepository {
  PostsRepository({required this.db, required this.uid});

  final FirebaseFirestore db;
  final String uid;

  CollectionReference<Map<String, dynamic>> get _posts =>
      db.collection('posts');

  /// Posts visible to this user (their friends' + their own), newest first.
  /// Needs the composite index on (audience array-contains, createdAt desc).
  Stream<List<Post>> watchFeed() {
    return _posts
        .where('audience', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Post.fromMap(d.id, d.data())).toList());
  }

  Future<PostAuthor> _author() async {
    final doc = await db
        .collection('users')
        .doc(uid)
        .collection('meta')
        .doc('profile')
        .get();
    return PostAuthor(
      username: (doc.data()?['username'] as String?) ?? '',
      displayName: (doc.data()?['displayName'] as String?) ?? '',
    );
  }

  /// The audience for a new post: the author's accepted friends plus self (so
  /// the author's own posts surface in their feed). A post-time snapshot.
  Future<List<String>> _audience() async {
    final snap =
        await db.collection('friendships').where('users', arrayContains: uid).get();
    final ids = <String>{uid};
    for (final d in snap.docs) {
      final data = d.data();
      if (data['status'] != 'accepted') continue;
      for (final u in (data['users'] as List? ?? const [])) {
        if ('$u' != uid) ids.add('$u');
      }
    }
    return ids.toList();
  }

  Future<void> _create(
    String type,
    Map<String, dynamic> payload, {
    String? caption,
    String? photoUrl,
  }) async {
    final author = await _author();
    final audience = await _audience();
    await _posts.add({
      'authorUid': uid,
      'author': author.toMap(),
      'type': type,
      'createdAt': FieldValue.serverTimestamp(),
      'caption': caption,
      'photoUrl': photoUrl,
      'audience': audience,
      ...payload,
    });
  }

  Future<void> createMilestonePost({
    required String taskName,
    required int milestoneHours,
    required int totalHours,
    String? caption,
    String? photoUrl,
  }) =>
      _create('milestone', {
        'taskName': taskName,
        'milestoneHours': milestoneHours,
        'totalHours': totalHours,
      }, caption: caption, photoUrl: photoUrl);

  Future<void> createStreakPost({
    required int streakDays,
    required List<String> habits,
    String? caption,
    String? photoUrl,
  }) =>
      _create('streak', {
        'streakDays': streakDays,
        'habits': habits,
      }, caption: caption, photoUrl: photoUrl);

  Future<void> createSessionPost({
    required String taskName,
    required int sessionSeconds,
    String? caption,
    String? photoUrl,
  }) =>
      _create('session', {
        'taskName': taskName,
        'sessionSeconds': sessionSeconds,
      }, caption: caption, photoUrl: photoUrl);
}

/// Null on the local/offline backend or before a uid exists.
final postsRepositoryProvider = Provider<PostsRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (!ref.watch(firebaseReadyProvider) || uid == null) return null;
  return PostsRepository(db: FirebaseFirestore.instance, uid: uid);
});

/// The friends-only feed stream (empty on the local backend).
final feedProvider = StreamProvider<List<Post>>((ref) {
  final repo = ref.watch(postsRepositoryProvider);
  if (repo == null) return Stream.value(const <Post>[]);
  return repo.watchFeed();
});

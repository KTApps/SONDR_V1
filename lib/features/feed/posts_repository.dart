import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import 'models/comment.dart';
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

  /// Returns the new post's id, so a later step can attach a photo by updating
  /// that post once Storage upload exists.
  Future<String> _create(
    String type,
    Map<String, dynamic> payload, {
    String? caption,
    String? photoUrl,
  }) async {
    final author = await _author();
    final audience = await _audience();
    final ref = await _posts.add({
      'authorUid': uid,
      'author': author.toMap(),
      'type': type,
      'createdAt': FieldValue.serverTimestamp(),
      'caption': caption,
      'photoUrl': photoUrl,
      'audience': audience,
      'likeCount': 0,
      'commentCount': 0,
      ...payload,
    });
    return ref.id;
  }

  // --- Likes -------------------------------------------------------------

  /// The post ids this user has liked — one stream off their own `likes`
  /// mirror, so cards can fill the heart without a per-post existence check.
  Stream<Set<String>> watchMyLikes() {
    return db
        .collection('users')
        .doc(uid)
        .collection('likes')
        .snapshots()
        .map((snap) => snap.docs.map((d) => d.id).toSet());
  }

  /// Like or unlike [postId]. Batched so the user's like mirror and the post's
  /// likeCount move together.
  Future<void> setLike(String postId, bool liked) async {
    final likeRef =
        db.collection('users').doc(uid).collection('likes').doc(postId);
    final postRef = _posts.doc(postId);
    final batch = db.batch();
    if (liked) {
      batch.set(likeRef, {'createdAt': FieldValue.serverTimestamp()});
      batch.update(postRef, {'likeCount': FieldValue.increment(1)});
    } else {
      batch.delete(likeRef);
      batch.update(postRef, {'likeCount': FieldValue.increment(-1)});
    }
    await batch.commit();
  }

  // --- Comments ----------------------------------------------------------

  /// A post's comments, oldest first.
  Stream<List<Comment>> watchComments(String postId) {
    return _posts
        .doc(postId)
        .collection('comments')
        .orderBy('createdAt')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Comment.fromMap(d.id, d.data())).toList());
  }

  /// Add a comment. Batched with the post's commentCount bump.
  Future<void> addComment(String postId, String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final author = await _author();
    final commentRef = _posts.doc(postId).collection('comments').doc();
    final batch = db.batch();
    batch.set(commentRef, {
      'authorUid': uid,
      'author': author.toMap(),
      'text': t,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_posts.doc(postId), {'commentCount': FieldValue.increment(1)});
    await batch.commit();
  }

  /// Delete one of the user's own comments. Batched with the count bump.
  Future<void> deleteComment(String postId, String commentId) async {
    final batch = db.batch();
    batch.delete(_posts.doc(postId).collection('comments').doc(commentId));
    batch.update(
        _posts.doc(postId), {'commentCount': FieldValue.increment(-1)});
    await batch.commit();
  }

  Future<String> createMilestonePost({
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

  Future<String> createStreakPost({
    required int streakDays,
    required List<String> habits,
    String? caption,
    String? photoUrl,
  }) =>
      _create('streak', {
        'streakDays': streakDays,
        'habits': habits,
      }, caption: caption, photoUrl: photoUrl);

  Future<String> createSessionPost({
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

/// The set of post ids the current user has liked (empty on the local backend).
final myLikedPostsProvider = StreamProvider<Set<String>>((ref) {
  final repo = ref.watch(postsRepositoryProvider);
  if (repo == null) return Stream.value(const <String>{});
  return repo.watchMyLikes();
});

/// A post's comments, oldest first (empty on the local backend).
final postCommentsProvider =
    StreamProvider.family<List<Comment>, String>((ref, postId) {
  final repo = ref.watch(postsRepositoryProvider);
  if (repo == null) return Stream.value(const <Comment>[]);
  return repo.watchComments(postId);
});

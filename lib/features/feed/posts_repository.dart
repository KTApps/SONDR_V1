import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../photos/local_first.dart';
import 'models/comment.dart';
import '../friends/friends_repository.dart';
import '../reports/report.dart';
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
        .map(
          (snap) => snap.docs.map((d) => Post.fromMap(d.id, d.data())).toList(),
        );
  }

  /// Someone's posts that I am in the audience of, newest first — what their
  /// profile shows. Bounded: a profile is a glance at what they have been
  /// doing, not an archive, and the count beside each heading is the length
  /// of this list (capped, so it can read "100+").
  ///
  /// The `audience array-contains` is not a nicety. The read rule requires
  /// the reader to be in the audience, and a query whose rule leans on
  /// per-document data it does not constrain fails WHOLESALE rather than
  /// omitting rows — so without this filter a profile does not show fewer
  /// posts, it errors. Needs the (authorUid, audience, createdAt) composite
  /// index. See test/rules/rules.test.mjs.
  Future<List<Post>> postsByAuthor(
    String authorUid, {
    int limit = kProfilePostsLimit,
    Source source = Source.serverAndCache,
  }) async {
    final snap = await _posts
        .where('authorUid', isEqualTo: authorUid)
        .where('audience', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get(GetOptions(source: source));
    return [for (final d in snap.docs) Post.fromMap(d.id, d.data())];
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
    final snap = await db
        .collection('friendships')
        .where('users', arrayContains: uid)
        .get();
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

  /// Returns the new post's id. [photos] are the post's attached images (already
  /// uploaded to the posts space via [uploadPostPhoto]); [caption] is written
  /// straight through (today's flows pass null, but the field is live).
  Future<String> _create(
    String type,
    Map<String, dynamic> payload, {
    String? caption,
    List<PostPhoto> photos = const [],
  }) async {
    final author = await _author();
    final audience = await _audience();
    final ref = await _posts.add({
      'authorUid': uid,
      'author': author.toMap(),
      'type': type,
      'createdAt': FieldValue.serverTimestamp(),
      'caption': caption,
      'photos': [for (final p in photos) p.toMap()],
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
    final likeRef = db
        .collection('users')
        .doc(uid)
        .collection('likes')
        .doc(postId);
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

  /// A post's comments, oldest first — the ones this reader is still in.
  ///
  /// The `array-contains` is not a nicety: the read rule requires the reader
  /// to be in the comment's audience, and a query whose rule leans on
  /// per-document data it does not constrain fails WHOLESALE rather than
  /// omitting rows. Without this filter the thread does not shorten, it
  /// errors. See test/rules/rules.test.mjs.
  Stream<List<Comment>> watchComments(String postId) {
    return _posts
        .doc(postId)
        .collection('comments')
        .where('audience', arrayContains: uid)
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((d) => Comment.fromMap(d.id, d.data())).toList(),
        );
  }

  /// Add a comment. Batched with the post's commentCount bump.
  Future<void> addComment(String postId, String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    final author = await _author();
    // The comment's audience is the post's, exactly — the rules check it
    // against the post and refuse anything else. A copy rather than a
    // reference because the commenter does not own the post and so could
    // never prune its audience; they can prune their own comment's.
    final post = await _posts.doc(postId).get();
    final audience = [
      for (final u in (post.data()?['audience'] as List? ?? const [])) '$u',
    ];
    final commentRef = _posts.doc(postId).collection('comments').doc();
    final batch = db.batch();
    batch.set(commentRef, {
      'authorUid': uid,
      'author': author.toMap(),
      'text': t,
      'audience': audience,
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(_posts.doc(postId), {'commentCount': FieldValue.increment(1)});
    await batch.commit();
  }

  /// Delete one of the user's own comments. Batched with the count bump.
  Future<void> deleteComment(String postId, String commentId) async {
    final batch = db.batch();
    batch.delete(_posts.doc(postId).collection('comments').doc(commentId));
    batch.update(_posts.doc(postId), {
      'commentCount': FieldValue.increment(-1),
    });
    await batch.commit();
  }

  /// Upload a photo to the user's own posts space and return both its download
  /// [url] and its Storage [storagePath], to wrap in a [PostPhoto] for a
  /// `create*` call. The path is retained on the post so [deletePost] can later
  /// remove the binary. Keyed by a fresh id so each attachment gets its own file.
  Future<({String url, String storagePath})> uploadPostPhoto(File file) async {
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final path = 'users/$uid/posts/$id.jpg';
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    return (url: url, storagePath: path);
  }

  /// Copy an existing owner-only Storage object (a gallery original at
  /// [sourceStoragePath]) into the friends-readable posts space, returning the
  /// new copy's {url, storagePath}. Download the bytes then re-upload via
  /// [uploadPostPhoto] — the private original is never referenced by the post.
  /// This is how a milestone share reuses prior in-app captures (the band pool)
  /// without exposing the gallery path (the same copy-first pattern as the
  /// day-detail session share).
  Future<({String url, String storagePath})> copyToPostsSpace(
    String sourceStoragePath,
  ) async {
    final bytes = await FirebaseStorage.instance
        .ref(sourceStoragePath)
        .getData(10 * 1024 * 1024);
    if (bytes == null) throw StateError('no photo bytes at $sourceStoragePath');
    final dir = Directory.systemTemp.createTempSync('sondr_postcopy');
    final file = File('${dir.path}/copy.jpg')..writeAsBytesSync(bytes);
    return uploadPostPhoto(file);
  }

  /// Delete a post and its posts-space photo binaries: each [PostPhoto]'s
  /// Storage object first (best-effort — a missing object is fine), then the
  /// doc. Touches **only** the post's own copies under the author's posts space;
  /// never the private gallery originals (`users/{uid}/photos`) or any logged
  /// time. Author-only is enforced at the rules layer. (The long-press delete
  /// UX lands in a later stage; this is the plumbing.)
  Future<void> deletePost(Post post) async {
    for (final photo in post.photos) {
      if (photo.storagePath.isEmpty) continue;
      try {
        await FirebaseStorage.instance.ref(photo.storagePath).delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') rethrow;
      }
    }
    await _posts.doc(post.id).delete();
  }

  Future<String> createMilestonePost({
    required String taskName,
    required int milestoneHours,
    required int totalHours,
    String? caption,
    List<PostPhoto> photos = const [],
  }) => _create(
    'milestone',
    {
      'taskName': taskName,
      'milestoneHours': milestoneHours,
      'totalHours': totalHours,
    },
    caption: caption,
    photos: photos,
  );

  Future<String> createSessionPost({
    required String taskName,
    required int sessionSeconds,
    String? caption,
    List<PostPhoto> photos = const [],
  }) => _create(
    'session',
    {'taskName': taskName, 'sessionSeconds': sessionSeconds},
    caption: caption,
    photos: photos,
  );
}

/// Null on the local/offline backend or before a uid exists.
final postsRepositoryProvider = Provider<PostsRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (!ref.watch(firebaseReadyProvider) || uid == null) return null;
  return PostsRepository(db: FirebaseFirestore.instance, uid: uid);
});

/// Everything in [items] whose author is not in [blockedUids].
///
/// Pure, so the filter — and above all its FAIL-OPEN behaviour — can be
/// tested without Firestore. An empty [blockedUids] must return everything:
/// the set is empty while the blocks stream loads and whenever it errors,
/// and a blank feed would be far worse than a visible blocked post.
List<T> withoutBlockedAuthors<T>(
  Iterable<T> items,
  Set<String> blockedUids,
  String Function(T) authorOf,
) =>
    blockedUids.isEmpty
        ? items.toList()
        : [
            for (final item in items)
              if (!blockedUids.contains(authorOf(item))) item,
          ];

/// The raw friends-only feed stream (empty on the local backend).
///
/// Private: everything reads [feedProvider], which is this with blocked
/// authors removed. Kept separate so changing the blocked set re-filters
/// without tearing down and re-establishing the Firestore subscription.
final _feedStreamProvider = StreamProvider<List<Post>>((ref) {
  final repo = ref.watch(postsRepositoryProvider);
  if (repo == null) return Stream.value(const <Post>[]);
  return repo.watchFeed();
});

/// The feed, with posts by blocked authors removed.
///
/// `audience` is frozen at post time, so unfriending someone — which is what
/// blocking does — cannot retroactively remove you from posts that already
/// exist. They keep arriving; this drops them on the way to the screen.
///
/// Still an `AsyncValue`, so `.when`/`.isLoading` at the call sites are
/// unchanged. Fails open: see [blockedUidsProvider]. Your own posts are
/// never touched — your uid cannot be in your own blocked set.
final feedProvider = Provider<AsyncValue<List<Post>>>((ref) {
  final blocked = ref.watch(blockedUidsProvider);
  final hidden = ref.watch(hiddenKeysProvider);
  return ref.watch(_feedStreamProvider).whenData(
        (posts) => withoutHidden(
          withoutBlockedAuthors(posts, blocked, (p) => p.authorUid),
          hidden,
          (p) => hiddenKey(ReportTarget.post, p.id),
        ),
      );
});

/// The set of post ids the current user has liked (empty on the local backend).
final myLikedPostsProvider = StreamProvider<Set<String>>((ref) {
  final repo = ref.watch(postsRepositoryProvider);
  if (repo == null) return Stream.value(const <String>{});
  return repo.watchMyLikes();
});

/// A post's raw comments, oldest first (empty on the local backend).
/// Private — read [postCommentsProvider].
final _postCommentsStreamProvider =
    StreamProvider.family<List<Comment>, String>((ref, postId) {
  final repo = ref.watch(postsRepositoryProvider);
  if (repo == null) return Stream.value(const <Comment>[]);
  return repo.watchComments(postId);
});

/// A post's comments with blocked authors removed.
///
/// A blocked person can still comment on a mutual friend's post — the block
/// stops the two of you being friends, not their presence in someone else's
/// thread. This keeps them out of your view of it.
final postCommentsProvider =
    Provider.family<AsyncValue<List<Comment>>, String>((ref, postId) {
  final blocked = ref.watch(blockedUidsProvider);
  final hidden = ref.watch(hiddenKeysProvider);
  return ref.watch(_postCommentsStreamProvider(postId)).whenData(
        (list) => withoutHidden(
          withoutBlockedAuthors(list, blocked, (c) => c.authorUid),
          hidden,
          (c) => hiddenKey(ReportTarget.comment, '$postId/${c.id}'),
        ),
      );
});

/// How many of someone's posts a profile reads. Past this the count reads
/// "100+" — the figure stops being interesting long before the page does.
const int kProfilePostsLimit = 100;

/// Someone's posts, as their profile shows them: what I am allowed to see,
/// newest first, read local-first so a profile opened twice paints from the
/// cache. Empty rather than throwing when there is nothing to show.
final profilePostsProvider =
    FutureProvider.autoDispose.family<List<Post>, String>((ref, authorUid) async {
  final repo = ref.watch(postsRepositoryProvider);
  if (repo == null) return const [];
  final hidden = ref.watch(hiddenKeysProvider);
  ref.keepAlive();
  try {
    final posts = await localFirst<List<Post>>(
      ref,
      read: (source) => repo.postsByAuthor(authorUid, source: source),
      isEmpty: (list) => list.isEmpty,
      same: (a, b) => sameIds([for (final p in a) p.id], [for (final p in b) p.id]),
    );
    return withoutHidden(
      posts,
      hidden,
      (p) => hiddenKey(ReportTarget.post, p.id),
    );
  } on FirebaseException catch (e) {
    debugPrint('SONDR profile posts error: ${e.code}');
    return const [];
  }
});

/// The count beside a heading: the list's length, or "100+" at the cap.
String profileCountLabel(int n) => n >= kProfilePostsLimit ? '$n+' : '$n';

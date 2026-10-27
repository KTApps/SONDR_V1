import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../photos/local_first.dart';
import '../notifications/notifications_repository.dart';
import 'models/comment.dart';
import '../friends/friends_repository.dart';
import '../reports/report.dart';
import 'band_story.dart' show SegmentUnit;
import 'models/post.dart';

/// Reads the friends-only feed and creates posts. Posts live in a top-level
/// `posts` collection; each carries an `audience` array (the author's accepted
/// friends at post time + self) so the feed is a single array-contains query and
/// the read rule needs no per-post friendship lookup.
class PostsRepository {
  PostsRepository({
    required this.db,
    required this.uid,
    NotificationsWriter? notifier,
  }) : notifier = notifier ?? FirestoreNotificationsWriter(db: db, uid: uid);

  /// Puts a notice beside each action: a like, a comment, a reply, a
  /// milestone shared.
  final NotificationsWriter notifier;

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

  /// A fresh post id, made on the client, so a post can be written by id
  /// and a share retried without a second post.
  String newPostId() => _posts.doc().id;

  /// Who I am, as a post names its author.
  Future<PostAuthor> author() => _author();

  /// Who my posts reach: my accepted friends, and me.
  Future<List<String>> audience() => _audience();

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
    // A milestone is news: every friend the post reaches hears of it.
    // After the post, so a notice never points at nothing; batched under
    // the limit; a failure here never undoes the post.
    if (type == 'milestone') {
      try {
        await _tellFriends(
          audience,
          type: NotificationType.milestone,
          actorHandle: author.username,
          postId: ref.id,
          taskName: payload['taskName'] as String?,
          hours: payload['milestoneHours'] as int?,
        );
      } catch (e) {
        debugPrint('SONDR milestone notices error: ${e.runtimeType}');
      }
    }
    return ref.id;
  }

  static const int _batchLimit = 450;

  Future<void> _tellFriends(
    List<String> audience, {
    required NotificationType type,
    required String actorHandle,
    required String postId,
    String? taskName,
    int? hours,
  }) async {
    final friends = [for (final u in audience) if (u != uid) u];
    for (var i = 0; i < friends.length; i += _batchLimit) {
      final batch = db.batch();
      for (final u in friends.skip(i).take(_batchLimit)) {
        notifier.add(
          batch,
          recipientUid: u,
          type: type,
          actorHandle: actorHandle,
          postId: postId,
          taskName: taskName,
          hours: hours,
        );
      }
      await batch.commit();
    }
  }

  /// One post by id, or null if it is gone or does not reach this user.
  /// What a notification opens.
  Future<Post?> fetchPost(String postId) async {
    try {
      final doc = await _posts.doc(postId).get();
      final data = doc.data();
      if (data == null) return null;
      return Post.fromMap(doc.id, data);
    } catch (e) {
      debugPrint('SONDR post fetch error: ${e.runtimeType}');
      return null;
    }
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

  /// Like or unlike [postId]. One batch, three writes, all or none: the
  /// user's own mirror (what fills the heart), the post's copy
  /// (`posts/{id}/likes/{uid}`, what the author's Likes sheet lists), and
  /// the counter on the post.
  ///
  /// [authorUid] is who to tell; the writer says nothing to yourself.
  Future<void> setLike(String postId, bool liked, {String? authorUid}) async {
    final me = await _author();
    final likeRef = db
        .collection('users')
        .doc(uid)
        .collection('likes')
        .doc(postId);
    final postRef = _posts.doc(postId);
    final onPost = postRef.collection('likes').doc(uid);
    final batch = db.batch();
    if (liked) {
      batch.set(likeRef, {'createdAt': FieldValue.serverTimestamp()});
      batch.set(onPost, {'at': FieldValue.serverTimestamp()});
      batch.update(postRef, {'likeCount': FieldValue.increment(1)});
      if (authorUid != null) {
        notifier.add(
          batch,
          recipientUid: authorUid,
          type: NotificationType.like,
          actorHandle: me.username,
          postId: postId,
        );
      }
    } else {
      batch.delete(likeRef);
      batch.delete(onPost);
      batch.update(postRef, {'likeCount': FieldValue.increment(-1)});
    }
    await batch.commit();
  }

  /// Who liked [postId], newest first. Readable by anyone the post
  /// reaches; the author opens it from the word "Likes" on their own post.
  /// Likes made before the post kept its own copy are not here — the sheet
  /// starts from the day it existed.
  Stream<List<PostLike>> watchLikes(String postId) {
    return _posts
        .doc(postId)
        .collection('likes')
        .orderBy('at', descending: true)
        .snapshots()
        .map(
          (snap) => [
            for (final d in snap.docs)
              PostLike(uid: d.id, at: _toTime(d.data()['at'])),
          ],
        );
  }

  static DateTime? _toTime(dynamic v) {
    if (v == null) return null;
    try {
      return (v as dynamic).toDate() as DateTime;
    } catch (_) {
      return null;
    }
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

  /// Add a comment — or a reply, when [parentId] names a top-level
  /// comment on this post. A reply to a reply attaches to the same parent;
  /// the rules refuse anything deeper. Batched with the post's commentCount
  /// bump, and with the notices: the post's author hears of a comment, the
  /// parent's author of a reply (and the post's author too, if different).
  Future<void> addComment(String postId, String text, {String? parentId}) async {
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
    final postAuthor = (post.data()?['authorUid'] as String?) ?? '';
    String? parentAuthor;
    if (parentId != null) {
      final parent = await _posts
          .doc(postId)
          .collection('comments')
          .doc(parentId)
          .get();
      parentAuthor = parent.data()?['authorUid'] as String?;
    }
    final commentRef = _posts.doc(postId).collection('comments').doc();
    final batch = db.batch();
    batch.set(commentRef, {
      'authorUid': uid,
      'author': author.toMap(),
      'text': t,
      'audience': audience,
      'createdAt': FieldValue.serverTimestamp(),
      'parentId': ?parentId,
    });
    batch.update(_posts.doc(postId), {'commentCount': FieldValue.increment(1)});
    if (parentId == null) {
      notifier.add(
        batch,
        recipientUid: postAuthor,
        type: NotificationType.comment,
        actorHandle: author.username,
        postId: postId,
        commentId: commentRef.id,
      );
    } else {
      if (parentAuthor != null) {
        notifier.add(
          batch,
          recipientUid: parentAuthor,
          type: NotificationType.reply,
          actorHandle: author.username,
          postId: postId,
          commentId: commentRef.id,
        );
      }
      if (postAuthor != parentAuthor) {
        notifier.add(
          batch,
          recipientUid: postAuthor,
          type: NotificationType.comment,
          actorHandle: author.username,
          postId: postId,
          commentId: commentRef.id,
        );
      }
    }
    await batch.commit();
  }

  /// Delete one of the user's own comments — and, if it was a parent, the
  /// replies under it, in the same batch (the rules let a parent's author
  /// take those down). The count moves by however many went.
  Future<void> deleteComment(String postId, String commentId) async {
    final comments = _posts.doc(postId).collection('comments');
    final replies = await comments.where('parentId', isEqualTo: commentId).get();
    final batch = db.batch();
    batch.delete(comments.doc(commentId));
    for (final r in replies.docs) {
      batch.delete(r.reference);
    }
    batch.update(_posts.doc(postId), {
      'commentCount': FieldValue.increment(-(1 + replies.docs.length)),
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
    final bytes = await photoBytes(sourceStoragePath);
    final dir = Directory.systemTemp.createTempSync('sondr_postcopy');
    final file = File('${dir.path}/copy.jpg')..writeAsBytesSync(bytes);
    return uploadPostPhoto(file);
  }

  /// The bytes of an owner-only Storage object — a gallery original — for
  /// a share that both copies it to the posts space and draws it into the
  /// cover, so it is fetched once.
  Future<Uint8List> photoBytes(String sourceStoragePath) async {
    final bytes = await FirebaseStorage.instance
        .ref(sourceStoragePath)
        .getData(10 * 1024 * 1024);
    if (bytes == null) throw StateError('no photo bytes at $sourceStoragePath');
    return bytes;
  }

  /// Delete a post and its posts-space photo binaries: each [PostPhoto]'s
  /// Storage object first (best-effort — a missing object is fine), then the
  /// doc. Touches **only** the post's own copies under the author's posts space;
  /// never the private gallery originals (`users/{uid}/photos`) or any logged
  /// time. Author-only is enforced at the rules layer. (The long-press delete
  /// UX lands in a later stage; this is the plumbing.)
  Future<void> deletePost(Post post) async {
    final binaries = [
      for (final photo in post.photos) photo.storagePath,
      // The cover and the thumbnail went up beside the photos and come
      // down with them.
      if (post is MilestonePost) ?post.coverStoragePath,
      if (post is MilestonePost) ?post.thumbStoragePath,
    ];
    for (final path in binaries) {
      if (path.isEmpty) continue;
      try {
        await FirebaseStorage.instance.ref(path).delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') rethrow;
      }
    }
    await _posts.doc(post.id).delete();
  }

  /// [segments] and [unit] are the story: the band's effort, session by
  /// session. [cover] is the cover drawn at share time and [thumb] the
  /// collage alone, small, both uploaded like photos. All additive: a post
  /// without them is an old one and still reads.
  Future<String> createMilestonePost({
    required String taskName,
    required int milestoneHours,
    required int totalHours,
    String? caption,
    List<PostPhoto> photos = const [],
    List<PostSegment> segments = const [],
    SegmentUnit? unit,
    ({String url, String storagePath})? cover,
    ({String url, String storagePath})? thumb,
  }) => _create(
    'milestone',
    {
      'taskName': taskName,
      'milestoneHours': milestoneHours,
      'totalHours': totalHours,
      if (segments.isNotEmpty && unit != null) ...{
        'sessions': [for (final s in segments) s.toMap()],
        'unit': unit.name,
      },
      if (cover != null) ...{
        'coverUrl': cover.url,
        'coverStoragePath': cover.storagePath,
      },
      if (thumb != null) ...{
        'thumbUrl': thumb.url,
        'thumbStoragePath': thumb.storagePath,
      },
    },
    caption: caption,
    photos: photos,
  );

  /// [bandSeconds]: the task's seconds into its band after this session,
  /// for the card's ring.
  Future<String> createSessionPost({
    required String taskName,
    required int sessionSeconds,
    String? caption,
    List<PostPhoto> photos = const [],
    int? bandSeconds,
  }) => _create(
    'session',
    {
      'taskName': taskName,
      'sessionSeconds': sessionSeconds,
      'bandSeconds': ?bandSeconds,
    },
    caption: caption,
    photos: photos,
  );
}

/// One like on a post: who, and when. The name comes from their public
/// profile, looked up by the sheet.
class PostLike {
  const PostLike({required this.uid, required this.at});

  final String uid;

  /// Null only between the local write and the server stamp landing.
  final DateTime? at;
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

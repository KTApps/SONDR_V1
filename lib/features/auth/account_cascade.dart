import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../feed/posts_repository.dart';
import '../friends/content_prune.dart';

/// Every subcollection under `users/{uid}`.
///
/// This list IS the contract: a client cannot ask Firestore what a
/// document's subcollections are — `listCollections` is admin-only — so
/// anything added to a user's space later has to be added here too, or
/// deleting an account will quietly leave it behind. `test/account_cascade_test.dart`
/// reads the source for `users/{uid}/<name>` paths and fails if this list
/// and the code disagree.
const List<String> kUserSubcollections = [
  'meta',
  'tasks',
  'habitDays',
  'photos',
  'collages',
  'likes',
  'hidden',
  'sessions',
];

/// The Storage prefixes an account owns, under which every object of theirs
/// lives (see storage.rules).
const List<String> kUserStoragePrefixes = ['photos', 'posts'];

/// The account's files in Storage, as a seam.
///
/// Storage is a plugin with nothing on the other end of it in a widget
/// test, and the cascade's ORDER is the thing worth testing — so the bytes
/// live behind this.
abstract interface class AccountFiles {
  /// Every object under [prefix], paged to the end.
  Future<List<String>> list(String prefix);

  Future<void> delete(String path);
}

class FirebaseAccountFiles implements AccountFiles {
  FirebaseAccountFiles({FirebaseStorage? storage})
    : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// A page at a time, because `listAll` is one request per 1000 objects
  /// with no bound on how many it will make, and an account with a long
  /// history has more photos than that. A post's files sit in a folder
  /// of its own under `posts`, so each folder found is listed in turn.
  @override
  Future<List<String>> list(String prefix) async {
    final found = <String>[];
    final folders = <String>[];
    final root = _storage.ref(prefix);
    String? token;
    do {
      final page = await root.list(
        ListOptions(maxResults: 100, pageToken: token),
      );
      found.addAll([for (final item in page.items) item.fullPath]);
      folders.addAll([for (final p in page.prefixes) p.fullPath]);
      token = page.nextPageToken;
    } while (token != null);
    for (final folder in folders) {
      found.addAll(await list(folder));
    }
    return found;
  }

  @override
  Future<void> delete(String path) => _storage.ref(path).delete();
}

/// Deleting everything an account leaves behind.
///
/// An interface so the flow above it can be tested without a Firestore —
/// what that test is about is the ORDER of the flow's steps, and whether a
/// cancelled re-authentication reaches this one at all.
abstract interface class AccountErasure {
  /// Returns the photo URLs the account owned, so their disk-cache entries
  /// can be evicted once the data behind them is gone.
  Future<Set<String>> run();
}

/// Everything an account leaves behind, deleted — as the account itself.
///
/// There are no Cloud Functions in this project, so this runs on the client
/// as the departing user, and every delete it makes is one the rules
/// already allow (see `what a leaving account may delete` in
/// test/rules/rules.test.mjs).
///
/// **Every step is idempotent.** A step that fails stops the run, and
/// whatever it had already deleted stays deleted — so the caller keeps the
/// account alive, says so, and a second attempt carries on from wherever
/// the first one stopped. Nothing here reads a count and writes it back;
/// the counters move by `increment`, inside the same batch as the document
/// whose existence justifies the move.
///
/// Two things are left behind on purpose:
///
/// 1. **Blocks other people placed on them.** Those documents are the other
///    person's, and letting a departing account delete them would let
///    anyone clear themselves off somebody else's block list.
/// 2. **Their uid inside old `audience` arrays.** An audience is frozen at
///    write time and belongs to the post's author; a uid in one is not
///    readable by anybody and names nothing once the account is gone.
///
/// Comments other people wrote on their posts used to survive too, and no
/// longer do: with the post gone such a comment is unreadable to everyone
/// — its read rule needs the post's audience — so it was litter nobody
/// could ever reach or remove. The post's author now clears what is under
/// their own post before the post itself goes; see [deletePostContents]
/// for the ordering, and firestore.rules for the grant it needs.
///
/// One thing under a post still cannot be reached: the mirror a liker
/// keeps of a like made before the post kept its own copy of it. The
/// author finds the likers through those copies, so a like with none is
/// invisible to them. It names a post that no longer exists and is inert.
class AccountCascade implements AccountErasure {
  AccountCascade({
    required this.db,
    required this.files,
    required this.audiences,
    required this.uid,
  });

  final FirebaseFirestore db;
  final AccountFiles files;

  /// Reused from the prune: `mine()` is already the one collection-group
  /// query the rules allow for "my comments, wherever they are", plus my
  /// posts. The cascade deletes those paths instead of pruning them.
  final PrunableAudiences audiences;

  final String uid;

  /// Firestore's limit is 500 writes per batch.
  static const int batchLimit = 450;

  /// In the order it has to happen. See the step comments for why.
  @override
  Future<Set<String>> run() async {
    // Everything that has to be READ before it is deleted out from under
    // us: which posts are mine, where my comments are, the handle to give
    // back, and the Storage path of every file either of them names.
    // BOTH filters, and the order the composite index carries: the posts
    // read rule grants on `audience` and nothing else, so a query that does
    // not constrain it cannot be proved safe for every document it might
    // match — and Firestore refuses the whole query, even when the result
    // would be empty. This is the exact shape a profile's own posts query
    // uses (PostsRepository.postsByAuthor), served by the live
    // (authorUid, audience, createdAt) index.
    //
    // Nothing of theirs can be missed by filtering on it: every version of
    // the create path seeds the audience with the author's own uid, and the
    // only thing that ever removes a uid from an audience refuses to remove
    // the author's own.
    final myPosts = await db
        .collection('posts')
        .where('authorUid', isEqualTo: uid)
        .where('audience', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .get();
    final myPostIds = {for (final post in myPosts.docs) post.id};
    final myComments = [
      for (final path in await audiences.mine())
        if (!_isPost(path)) path,
    ];
    final recordedFiles = await _recordedFiles(myPosts.docs);
    final photoUrls = await _photoUrls(myPosts.docs);
    final handle = await _myHandle();

    // Likes first: a like on one of MY posts needs that post to still be
    // there, or the counter write in its batch fails.
    await _notifications();
    await _noticesISent();
    await _likes(myPostIds);
    await _comments(myComments, myPostIds);
    await _posts(myPostIds);
    await _storage(recordedFiles);
    await _mirror();
    await _friendships();
    await _blocksIPlaced();
    await _publicProfile();
    await _invite();
    await _handleDoc(handle);
    // Last, because the handle above is read out of it.
    await _userSpace();
    return photoUrls;
  }

  /// Every photo URL the account owned. Nothing is deleted by these — they
  /// are what the device's image cache is keyed by.
  Future<Set<String>> _photoUrls(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> myPosts,
  ) async {
    final urls = <String>{};
    void add(Object? value) {
      if (value is String && value.isNotEmpty) urls.add(value);
    }

    for (final post in myPosts) {
      for (final photo in (post.data()['photos'] as List? ?? const [])) {
        if (photo is Map) add(photo['url']);
      }
    }
    final photos = await db
        .collection('users')
        .doc(uid)
        .collection('photos')
        .get();
    for (final photo in photos.docs) {
      add(photo.data()['photoUrl']);
    }
    return urls;
  }

  /// Every Storage object Firestore knows this account owns: the binary
  /// behind each gallery photo, and each image attached to a post.
  ///
  /// Read up front and deleted by path, so the files go even if listing is
  /// refused — see [_storage].
  Future<Set<String>> _recordedFiles(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> myPosts,
  ) async {
    final paths = <String>{};
    void add(Object? value) {
      // 'unused' is what a seeded photo carries where a real one has a path.
      if (value is String && value.isNotEmpty && value != 'unused') {
        paths.add(value);
      }
    }

    for (final post in myPosts) {
      for (final photo in (post.data()['photos'] as List? ?? const [])) {
        if (photo is Map) add(photo['storagePath']);
      }
    }
    final photos = await db
        .collection('users')
        .doc(uid)
        .collection('photos')
        .get();
    for (final photo in photos.docs) {
      add(photo.data()['storagePath']);
    }
    return paths;
  }

  static bool _isPost(String path) {
    final parts = path.split('/');
    return parts.length == 2 && parts.first == 'posts';
  }

  /// The handle to give back, from the profile that holds it. Empty when
  /// one was never claimed, or when the document has already gone in an
  /// earlier attempt — in which case the handle went with it.
  Future<String> _myHandle() async {
    try {
      final doc = await db
          .collection('users')
          .doc(uid)
          .collection('meta')
          .doc('profile')
          .get();
      return (doc.data()?['username'] as String?) ?? '';
    } on FirebaseException catch (e) {
      debugPrint('SONDR delete: no handle to release (${e.code})');
      return '';
    }
  }

  /// Their likes, and the like counts those likes are holding up.
  ///
  /// One batch per post rather than one for all of them: a post can be
  /// deleted by its own author at any moment, and a single missing
  /// document would fail a batch carrying hundreds of other people's
  /// counters with it.
  /// What was written TO me: notifications/{me}/items. Top-level rather
  /// than under users/{me}, because other people write there, so it is
  /// not in [kUserSubcollections] and needs its own step.
  Future<void> _notifications() async {
    final items = db.collection('notifications').doc(uid).collection('items');
    while (true) {
      final page = await items.limit(batchLimit).get();
      if (page.docs.isEmpty) break;
      final batch = db.batch();
      for (final d in page.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (page.docs.length < batchLimit) break;
    }
  }

  /// A like is three documents: the mirror in their own space, the copy
  /// under the post that the author's Likes sheet lists, and the count on
  /// the post. All three move in ONE batch, so a re-run either finds the
  /// mirror gone and does nothing, or repeats a batch that never landed —
  /// the counter can never be taken off twice. The copy under the post is
  /// deleted unconditionally: a like from before the post kept its own
  /// copy has none, and deleting a document that is not there costs
  /// nothing and fails nothing.
  /// What they wrote into OTHER people's inboxes — a like, a comment, a
  /// reply, a milestone. Their own inbox goes in [_notifications]; this is
  /// the other side of it, so deleting an account takes its name out of
  /// everyone else's notices too.
  ///
  /// A collection group over `items` by `actorUid`, which needs that
  /// field indexed at collection-group scope (see firestore.indexes.json)
  /// and the read granted to the actor as well as the recipient (see
  /// firestore.rules).
  Future<void> _noticesISent() async {
    final sent = await db
        .collectionGroup('items')
        .where('actorUid', isEqualTo: uid)
        .get();
    final theirs = [
      for (final d in sent.docs)
        if (d.reference.parent.parent?.id != uid) d.reference,
    ];
    for (var i = 0; i < theirs.length; i += batchLimit) {
      final batch = db.batch();
      for (final ref in theirs.skip(i).take(batchLimit)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  Future<void> _likes(Set<String> myPostIds) async {
    final likes = await db
        .collection('users')
        .doc(uid)
        .collection('likes')
        .get();
    for (final like in likes.docs) {
      final postId = like.id;
      final onPost = db.collection('posts').doc(postId).collection('likes').doc(uid);
      // My own posts are deleted whole, counters, copies and all.
      if (myPostIds.contains(postId)) {
        await like.reference.delete();
        continue;
      }
      try {
        final batch = db.batch();
        batch.delete(like.reference);
        batch.delete(onPost);
        batch.update(db.collection('posts').doc(postId), {
          'likeCount': FieldValue.increment(-1),
        });
        await batch.commit();
      } on FirebaseException catch (e) {
        // The post is gone, or no longer ours to reach. There is no
        // counter left to put right, so the like is removed on its own.
        //
        // ONLY those two: anything else — a dropped connection, a
        // contended document — is a batch that may yet land, and
        // swallowing it here would delete the mirror and leave the count
        // standing with nothing a retry could match it against. Those are
        // rethrown with the mirror intact, so running again starts from
        // the same place and finishes.
        if (e.code != 'not-found' && e.code != 'permission-denied') rethrow;
        debugPrint('SONDR delete: like counter skipped (${e.code})');
        await like.reference.delete();
        try {
          await onPost.delete();
        } on FirebaseException catch (e) {
          debugPrint('SONDR delete: like copy skipped (${e.code})');
        }
      }
    }
  }

  /// Their comments, wherever they are, and the comment counts they hold up.
  Future<void> _comments(List<String> paths, Set<String> myPostIds) async {
    for (final path in paths) {
      final ref = db.doc(path);
      final postId = path.split('/')[1];
      if (myPostIds.contains(postId)) {
        await ref.delete();
        continue;
      }
      try {
        final batch = db.batch();
        batch.delete(ref);
        batch.update(db.collection('posts').doc(postId), {
          'commentCount': FieldValue.increment(-1),
        });
        await batch.commit();
      } on FirebaseException catch (e) {
        debugPrint('SONDR delete: comment counter skipped (${e.code})');
        await ref.delete();
      }
    }
  }

  /// Their posts: what is under each one first — the likes, the mirrors
  /// their likers keep, the comments other people left — then the
  /// documents. Same order and same reason as [PostsRepository.deletePost]:
  /// the post is what the rules for its own contents are proved against.
  Future<void> _posts(Set<String> ids) async {
    final all = ids.toList();
    for (final id in all) {
      await deletePostContents(db, id, batchLimit: batchLimit);
    }
    for (var i = 0; i < all.length; i += batchLimit) {
      final batch = db.batch();
      for (final id in all.skip(i).take(batchLimit)) {
        batch.delete(db.collection('posts').doc(id));
      }
      await batch.commit();
    }
  }

  /// Their files: the ones Firestore named, then a sweep for anything else
  /// under the two prefixes.
  ///
  /// The recorded paths are the ones that matter and they need no listing
  /// permission, so they are deleted first and a failure there stops the
  /// run — leaving somebody's photos behind while deleting their account is
  /// exactly what this is for. An object already gone is not a failure: a
  /// retry finds the first attempt's work done.
  ///
  /// The sweep is for an upload whose document never landed, which only a
  /// listing can find. It is allowed to fail without stopping anything:
  /// listing is checked against the PREFIX (see storage.rules), and if that
  /// grant is ever wrong, no account could be deleted at all — a far worse
  /// outcome than an orphaned file nothing refers to.
  Future<void> _storage(Set<String> recorded) async {
    for (final path in recorded) {
      try {
        await files.delete(path);
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') rethrow;
      }
    }
    for (final prefix in kUserStoragePrefixes) {
      try {
        for (final path in await files.list('users/$uid/$prefix')) {
          try {
            await files.delete(path);
          } on FirebaseException catch (e) {
            if (e.code != 'object-not-found') rethrow;
          }
        }
      } catch (e) {
        debugPrint('SONDR delete: orphan sweep skipped (${e.runtimeType})');
      }
    }
  }

  /// The friend mirror: their list, and their half in each friend's list.
  ///
  /// Both halves always move together — the same pairing unfriending has
  /// always used — so a friend is never left with a one-sided entry.
  Future<void> _mirror() async {
    final friends = await db
        .collection('publicProfiles')
        .doc(uid)
        .collection('friends')
        .get();
    for (final friend in friends.docs) {
      await db
          .collection('publicProfiles')
          .doc(friend.id)
          .collection('friends')
          .doc(uid)
          .delete();
      await friend.reference.delete();
    }
  }

  Future<void> _friendships() async {
    final mine = await db
        .collection('friendships')
        .where('users', arrayContains: uid)
        .get();
    for (var i = 0; i < mine.docs.length; i += batchLimit) {
      final batch = db.batch();
      for (final d in mine.docs.skip(i).take(batchLimit)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  /// The blocks they placed. The ones placed ON them are somebody else's
  /// document and stay — see the class comment.
  Future<void> _blocksIPlaced() async {
    final mine = await db
        .collection('blocks')
        .where('blocker', isEqualTo: uid)
        .get();
    for (var i = 0; i < mine.docs.length; i += batchLimit) {
      final batch = db.batch();
      for (final d in mine.docs.skip(i).take(batchLimit)) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  Future<void> _publicProfile() =>
      db.collection('publicProfiles').doc(uid).delete();

  /// Who invited them. Theirs, and only ever theirs to remove — deleting a
  /// missing one is an allowed no-op, which is what an account that was
  /// never invited does here.
  Future<void> _invite() => db.collection('invites').doc(uid).delete();

  /// Give the handle back, so the next person can have it.
  Future<void> _handleDoc(String handle) async {
    if (handle.isEmpty) return;
    await db.collection('usernames').doc(handle).delete();
  }

  /// Their own space: every subcollection in [kUserSubcollections], then
  /// the document itself.
  Future<void> _userSpace() async {
    for (final name in kUserSubcollections) {
      final collection = db
          .collection('users')
          .doc(uid)
          .collection(name);
      while (true) {
        final page = await collection.limit(batchLimit).get();
        if (page.docs.isEmpty) break;
        final batch = db.batch();
        for (final d in page.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
        if (page.docs.length < batchLimit) break;
      }
    }
    await db.collection('users').doc(uid).delete();
  }
}

/// Null on the local backend and before a uid exists.
final accountCascadeProvider = Provider<AccountErasure?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (!ref.watch(firebaseReadyProvider) || uid == null) return null;
  final db = FirebaseFirestore.instance;
  return AccountCascade(
    db: db,
    files: FirebaseAccountFiles(),
    audiences: FirestoreAudiences(db: db, uid: uid),
    uid: uid,
  );
});

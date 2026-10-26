import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../profile/friend_mirror.dart';
import 'audience_widen.dart';
import 'content_prune.dart';
import 'models/block.dart';
import 'models/friendship.dart';

/// A user-facing failure (handle not found, already friends, no handle set).
/// Its [message] is safe to show directly.
class FriendException implements Exception {
  const FriendException(this.message);
  final String message;
}

/// A handle as stored: trimmed, lowercase, without a leading `@`.
String normalizeHandle(String raw) =>
    raw.trim().toLowerCase().replaceFirst(RegExp(r'^@'), '');

/// One person found by handle: what to show, and whose profile it is.
///
/// The uid matters as much as the handle now — a search result opens that
/// person's profile, and `usernames/{handle}` is the only place the two are
/// written down together.
class HandleMatch {
  const HandleMatch({required this.handle, required this.uid});

  final String handle;
  final String uid;
}

/// The handles in [candidates] (handle -> owner uid) that [blockedUids] does
/// not cover, in order.
///
/// Pure, so the filter is testable without Firestore. A candidate with no uid
/// is dropped: a usernames entry with no owner is malformed and unusable —
/// and now also unopenable, since a profile is addressed by uid.
List<HandleMatch> handlesNotBlocked(
  Iterable<MapEntry<String, String?>> candidates,
  Set<String> blockedUids,
) =>
    [
      for (final c in candidates)
        if (c.value != null && !blockedUids.contains(c.value))
          HandleMatch(handle: c.key, uid: c.value!),
    ];

/// What a friend request should be refused for, before anything is written
/// — or null to go ahead.
///
/// Pure, and deliberately says NOTHING about handles being required. A
/// profile is reached by uid and the public document that would name its
/// owner may not exist; refusing the add for want of a handle is search's
/// rule, not a profile's, and applying it here is what made Add friend on a
/// profile answer "Enter a handle." and send nothing.
FriendException? addFriendRefusal({
  required String myUid,
  required String targetUid,
  required String myHandle,
  required String handle,
  required Set<String> blockedByMe,
  required Friendship? existing,
}) {
  if (targetUid.isEmpty || targetUid == myUid) {
    return const FriendException('That is your own profile.');
  }
  if (myHandle.isEmpty) {
    return const FriendException('Set a handle before adding friends.');
  }
  // Someone this user has blocked is refused in the same words as someone
  // who does not exist — and the rules refuse the write in the other
  // direction with the same words again, so a block stays invisible.
  if (blockedByMe.contains(targetUid)) {
    return FriendException(addFriendUnavailable(handle));
  }
  if (existing != null) {
    final named = handle.isEmpty ? '' : ' with @$handle';
    return FriendException(existing.isAccepted
        ? "You're already friends$named."
        : 'There’s already a pending request$named.');
  }
  return null;
}

/// The one wording a refusal that must not disclose anything takes. Named
/// where the page knows a handle, because that is what search says and the
/// two must not be told apart.
String addFriendUnavailable(String handle) => handle.isEmpty
    ? 'That person is no longer available.'
    : 'No one found with the handle @$handle.';

/// Reads and mutates the `friendships` collection for the current [uid]. All
/// reads are scoped by `array-contains uid`, matching the security rule that a
/// user can only see friendships they're part of.
class FriendsRepository {
  FriendsRepository({
    required this.db,
    required this.uid,
    ContentPruner? pruner,
    AudienceWidener? widener,
  }) : pruner =
           pruner ??
           ContentPruner(
             uid: uid,
             audiences: FirestoreAudiences(db: db, uid: uid),
             pending: PrefsPendingPrunes(),
           ) {
    this.widener =
        widener ??
        AudienceWidener(
          uid: uid,
          audiences: FirestoreWidenableAudiences(db: db, uid: uid),
          blocked: _blockedByMe,
        );
  }

  final FirebaseFirestore db;
  final String uid;

  /// Takes the other person out of audiences this user already wrote.
  final ContentPruner pruner;

  /// Lets a new friend into audiences this user already wrote.
  late final AudienceWidener widener;

  CollectionReference<Map<String, dynamic>> get _friendships =>
      db.collection('friendships');

  CollectionReference<Map<String, dynamic>> get _blocks =>
      db.collection('blocks');

  /// Every block this user has placed. Only the blocker can read these, so a
  /// blocked person is never told.
  Stream<List<Block>> watchBlocked() {
    return _blocks
        .where('blocker', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs.map((d) => Block.fromMap(d.data())).toList());
  }

  /// The uids this user has blocked, kept live from [watchBlocked].
  ///
  /// Cached from the STREAM rather than read per candidate. A `get()` of a
  /// block document that does not exist is DENIED, not empty — the read rule
  /// dereferences `resource.data.blocker` on a null resource — so reading one
  /// per candidate threw `permission-denied` and took search, sendRequest and
  /// accept down with it. A query filtered by `blocker == uid` has no such
  /// trap: every document it returns exists.
  Set<String> _blockedUids = const {};
  StreamSubscription<List<Block>>? _blockSub;
  Completer<void>? _primed;

  /// The people this user has blocked.
  ///
  /// Only THIS user's blocks. Whether the other person has blocked us is
  /// deliberately not asked: that is the rules' job, via `exists()` on the
  /// block id. A client able to ask could detect that it had been blocked,
  /// which is the one thing a block must not disclose.
  ///
  /// Fails OPEN. The rules are the real boundary and this is UX, so a blocks
  /// read that is denied, offline or slow filters nothing rather than break
  /// whatever called it.
  Future<Set<String>> _blockedByMe() async {
    if (_blockSub == null) {
      final completer = Completer<void>();
      _primed = completer;
      void prime() {
        if (!completer.isCompleted) completer.complete();
      }

      _blockSub = watchBlocked().listen(
        (list) {
          _blockedUids = {for (final b in list) b.blocked};
          prime();
        },
        onError: (Object _) {
          _blockedUids = const {};
          prime();
        },
      );
    }

    final pending = _primed;
    if (pending != null && !pending.isCompleted) {
      // Awaited once, so a search in the first moments after launch cannot
      // show someone this user has blocked. Bounded, so a stream that never
      // speaks holds nothing up for long.
      await pending.future
          .timeout(const Duration(seconds: 3), onTimeout: () {});
    }
    return _blockedUids;
  }

  /// Stop watching blocks. Called when the provider is disposed.
  void dispose() {
    _blockSub?.cancel();
    _blockSub = null;
  }

  /// Block [targetUid]: unfriend and record the block in one write, so a
  /// failure cannot leave the pair unfriended-but-unblocked or the reverse.
  Future<void> blockUser({
    required String targetUid,
    required String username,
    required String displayName,
  }) async {
    final batch = db.batch();
    batch.delete(_friendships.doc(Friendship.pairId(uid, targetUid)));
    // Their profile must stop listing us, and ours them, the moment the
    // friendship goes — either party may clear either half.
    removeFriendMirror(batch, db, uid, targetUid);
    batch.set(_blocks.doc(Block.idFor(uid, targetUid)), {
      'blocker': uid,
      'blocked': targetUid,
      'username': username,
      'displayName': displayName,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    // Not awaited: the block itself is the thing that must land, and the
    // prune is retried at launch until the server confirms it. Making the
    // button wait on every post and comment would be a network round trip
    // per batch for no benefit the owner can see.
    unawaited(pruner.pruneMyContentFor(targetUid));
  }

  /// Lift a block this user placed. The friendship is not restored — they
  /// would have to ask again, and nothing pruned is put back.
  Future<void> unblockUser(String blockedUid) =>
      _blocks.doc(Block.idFor(uid, blockedUid)).delete();

  Stream<List<Friendship>> watchAll() {
    return _friendships
        .where('users', arrayContains: uid)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Friendship.fromMap(d.id, d.data())).toList());
  }

  /// People whose handle starts with [prefix], alphabetical, excluding this
  /// user's own. Handles are the `usernames` doc ids, so this is a doc-id
  /// range query — no composite index needed.
  Future<List<HandleMatch>> searchHandles(
    String prefix, {
    int limit = 8,
  }) async {
    final h = normalizeHandle(prefix);
    if (h.isEmpty) return const [];
    final snap = await db
        .collection('usernames')
        .where(FieldPath.documentId, isGreaterThanOrEqualTo: h)
        .where(FieldPath.documentId, isLessThan: '$h\uf8ff')
        .limit(limit + 1)
        .get();
    final candidates = snap.docs
        .where((d) => d.data()['uid'] != uid)
        .take(limit)
        .toList();

    // People this user has blocked are not findable. The reverse direction —
    // someone who blocked US — is left to the rules on the write (see
    // [_blockedByMe]); search itself must not be able to detect it.
    return handlesNotBlocked(
      [for (final d in candidates) MapEntry(d.id, d.data()['uid'] as String?)],
      await _blockedByMe(),
    );
  }

  Future<FriendIdentity> _myIdentity() async {
    final doc = await db
        .collection('users')
        .doc(uid)
        .collection('meta')
        .doc('profile')
        .get();
    final username = (doc.data()?['username'] as String?) ?? '';
    if (username.isEmpty) {
      throw const FriendException('Set a handle before adding friends.');
    }
    return FriendIdentity(
      username: username,
      displayName: (doc.data()?['displayName'] as String?) ?? '',
    );
  }

  /// Send a friend request to whoever owns [handle]. Resolves the handle via
  /// the public usernames index, then adds by uid like everything else.
  ///
  /// The handle is required HERE because a handle is all this caller has —
  /// it is typed into a field. A profile adds by uid; see [sendRequestTo].
  Future<void> sendRequest(String handle) async {
    final h = normalizeHandle(handle);
    if (h.isEmpty) throw const FriendException('Enter a handle.');

    final me = await _myIdentity();
    if (h == me.username) {
      throw const FriendException("That's your own handle.");
    }

    final idx = await db.collection('usernames').doc(h).get();
    final targetUid = idx.data()?['uid'] as String?;
    if (!idx.exists || targetUid == null) {
      throw FriendException(addFriendUnavailable(h));
    }
    return sendRequestTo(targetUid, handle: h);
  }

  /// Send a friend request to [targetUid] — what a profile does.
  ///
  /// The handle is optional and is never read to decide anything: it is
  /// carried only so the pending row has something to print until they
  /// accept and write their own identity. A profile is addressed by uid,
  /// and the published document that would name its owner may not exist.
  Future<void> sendRequestTo(String targetUid, {String handle = ''}) async {
    final me = await _myIdentity();

    // Duplicate check via a query we're allowed to run (the same
    // array-contains shape as the stream) — NOT a direct get() on the pair
    // doc. Reading a not-yet-existent friendships doc is denied, because
    // the participant read rule dereferences resource.data.users on a null
    // resource.
    final mine = await _friendships.where('users', arrayContains: uid).get();
    final existingDoc = mine.docs
        .where((d) => (d.data()['users'] as List?)?.contains(targetUid) ?? false)
        .firstOrNull;

    final refusal = addFriendRefusal(
      myUid: uid,
      targetUid: targetUid,
      myHandle: me.username,
      handle: handle,
      blockedByMe: await _blockedByMe(),
      existing: existingDoc == null
          ? null
          : Friendship.fromMap(existingDoc.id, existingDoc.data()),
    );
    if (refusal != null) throw refusal;

    try {
      await _friendships
          .doc(Friendship.pairId(uid, targetUid))
          .set(_requestData(targetUid, me, handle));
    } on FirebaseException catch (e) {
      // For a well-formed request the create rule's only conditional
      // refusal is blockedEitherWay() — they blocked us. The same wording
      // as "no one found", so the block stays invisible.
      if (e.code == 'permission-denied') {
        throw FriendException(addFriendUnavailable(handle));
      }
      rethrow;
    }
  }

  /// The document a pending request is, in one place: it is written by the
  /// Add flow and again by the invite, and the two must not drift.
  Map<String, dynamic> _requestData(
    String targetUid,
    FriendIdentity me,
    String handle,
  ) => {
    'users': [uid, targetUid]..sort(),
    'requestedBy': uid,
    'status': 'pending',
    'profiles': {
      uid: {'username': me.username, 'displayName': me.displayName},
      targetUid: {'username': handle},
    },
    'createdAt': FieldValue.serverTimestamp(),
  };

  /// Record who invited this account, and ask to be their friend.
  ///
  /// One batch, so there is no state where the invite is recorded and the
  /// request is not — a half-written answer to a question asked once would
  /// never be asked again.
  ///
  /// The request is staged only when there is one to send. Already friends,
  /// already asked, or blocked in either direction: the invite still stands
  /// — who invited them is true regardless of what the two of them have
  /// done since — and nothing is written that the rules would refuse.
  ///
  /// Returns whether a request went with it, so the screen can say so.
  Future<bool> recordInvite({
    required String inviterUid,
    required String inviterHandle,
  }) async {
    final me = await _myIdentity();

    // The same duplicate check Add makes, and for the same reason: a get()
    // on a friendship that does not exist yet is denied.
    final mine = await _friendships.where('users', arrayContains: uid).get();
    final existingDoc = mine.docs
        .where((d) => (d.data()['users'] as List?)?.contains(inviterUid) ?? false)
        .firstOrNull;
    final refusal = addFriendRefusal(
      myUid: uid,
      targetUid: inviterUid,
      myHandle: me.username,
      handle: inviterHandle,
      blockedByMe: await _blockedByMe(),
      existing: existingDoc == null
          ? null
          : Friendship.fromMap(existingDoc.id, existingDoc.data()),
    );

    final batch = db.batch();
    batch.set(db.collection('invites').doc(uid), {
      'invitedBy': inviterUid,
      'invitedByHandle': inviterHandle,
      'at': FieldValue.serverTimestamp(),
    });
    if (refusal == null) {
      batch.set(
        _friendships.doc(Friendship.pairId(uid, inviterUid)),
        _requestData(inviterUid, me, inviterHandle),
      );
    }
    await batch.commit();
    return refusal == null;
  }

  /// Accept an incoming request, writing this user's identity into the doc so
  /// the requester can see who they're now friends with.
  Future<void> accept(String pairId) async {
    final me = await _myIdentity();
    final other = pairId.split('__').firstWhere((u) => u != uid, orElse: () => '');
    if (other.isNotEmpty && (await _blockedByMe()).contains(other)) {
      throw const FriendException('That request is no longer available.');
    }
    try {
      // One batch: the acceptance and both halves of the friend mirror. The
      // rules allow a mirror entry only where the friendship is accepted
      // AFTER the write lands (getAfter), which is exactly this.
      final batch = db.batch();
      batch.update(_friendships.doc(pairId), {
        'status': 'accepted',
        'acceptedAt': FieldValue.serverTimestamp(),
        'profiles.$uid': {
          'username': me.username,
          'displayName': me.displayName,
        },
      });
      if (other.isNotEmpty) addFriendMirror(batch, db, uid, other);
      await batch.commit();
    } on FirebaseException catch (e) {
      // Denied means the rules refused the accept across a block in either
      // direction. Neutral wording: it does not say which.
      if (e.code == 'permission-denied') {
        throw const FriendException('That request is no longer available.');
      }
      rethrow;
    }
    // Everything I posted before today reaches them now. Their side of it
    // — their posts to me — lands when their app next reconciles at
    // launch. Not awaited: the accept is done, and this can retry.
    if (other.isNotEmpty) unawaited(widener.widenFor({other}));
  }

  /// Decline an incoming request, cancel an outgoing one, or unfriend — all the
  /// same delete from a participant's side.
  ///
  /// Prunes the other party out of this user's existing posts and comments,
  /// the same as blocking. Not because unfriending needs to hide anything,
  /// but because blocking does: if only a block pruned, the posts going
  /// quiet would be the tell.
  ///
  /// A pair id is the two uids sorted and joined, so the other one is
  /// whichever half is not this user. A declined or cancelled REQUEST
  /// prunes too; the audiences simply contain nobody to remove, because a
  /// pending request was never in one.
  Future<void> remove(String pairId) async {
    final other = Friendship.otherIn(pairId, uid);
    final batch = db.batch();
    batch.delete(_friendships.doc(pairId));
    // A declined or cancelled REQUEST has no mirror halves; deleting what
    // was never written is a no-op the rules allow, so this needs no branch.
    if (other != null && other.isNotEmpty) {
      removeFriendMirror(batch, db, uid, other);
    }
    await batch.commit();
    if (other != null) unawaited(pruner.pruneMyContentFor(other));
  }
}

/// Null on the local/offline backend or before a uid exists; friends require a
/// real Firestore user.
final friendsRepositoryProvider = Provider<FriendsRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (!ref.watch(firebaseReadyProvider) || uid == null) return null;
  final repo = FriendsRepository(db: FirebaseFirestore.instance, uid: uid);
  ref.onDispose(repo.dispose);
  return repo;
});

/// Every friendship the user is part of (any status). The screen and the
/// derived providers split it into friends / incoming / outgoing client-side,
/// avoiding a composite index for the 100-user test.
final friendshipsProvider = StreamProvider<List<Friendship>>((ref) {
  final repo = ref.watch(friendsRepositoryProvider);
  if (repo == null) return Stream.value(const <Friendship>[]);
  return repo.watchAll();
});

List<Friendship> _all(Ref ref) =>
    ref.watch(friendshipsProvider).value ?? const <Friendship>[];

final friendsProvider = Provider<List<Friendship>>(
    (ref) => _all(ref).where((f) => f.isAccepted).toList());

final incomingRequestsProvider = Provider<List<Friendship>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return const [];
  return _all(ref).where((f) => f.isIncoming(uid)).toList();
});

final outgoingRequestsProvider = Provider<List<Friendship>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return const [];
  return _all(ref).where((f) => f.isOutgoing(uid)).toList();
});

final friendCountProvider = Provider<int>((ref) => ref.watch(friendsProvider).length);

/// The uids this user has blocked, as a set, for filtering content.
///
/// FAILS OPEN. While the blocks stream is loading, or if it errors (rules
/// not deployed, offline), this is EMPTY and nothing is filtered — a broken
/// block read must never blank the feed. The rules are the boundary; this is
/// the courtesy of not showing you someone you walked away from.
///
/// Derived from the one [blockedAccountsProvider] stream, so filtering costs
/// no extra reads — per-item block lookups are what broke search before.
final blockedUidsProvider = Provider<Set<String>>((ref) {
  return ref.watch(blockedAccountsProvider).maybeWhen(
        data: (list) => {for (final b in list) b.blocked},
        orElse: () => const <String>{},
      );
});

/// The people this user has blocked. Empty when there is no backend.
final blockedAccountsProvider = StreamProvider<List<Block>>((ref) {
  final repo = ref.watch(friendsRepositoryProvider);
  if (repo == null) return Stream.value(const <Block>[]);
  return repo.watchBlocked();
});

/// Finish any prune a previous launch could not confirm.
///
/// A function rather than a value so the caller decides when it runs, and so
/// a test can override it without a Firestore instance. Does nothing when
/// there is no backend — there is nothing to prune on the local one.
final pendingPruneRunnerProvider = Provider<Future<void> Function()>((ref) {
  final repo = ref.watch(friendsRepositoryProvider);
  if (repo == null) return () async {};
  return repo.pruner.runPending;
});

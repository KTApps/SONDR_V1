import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
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

/// Reads and mutates the `friendships` collection for the current [uid]. All
/// reads are scoped by `array-contains uid`, matching the security rule that a
/// user can only see friendships they're part of.
class FriendsRepository {
  FriendsRepository({required this.db, required this.uid});

  final FirebaseFirestore db;
  final String uid;

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

  /// True when either side has blocked the other. Two direct gets rather than
  /// a query: the ids are derived, and a blocked user cannot read the doc that
  /// blocks them — but they can be denied by it.
  Future<bool> _blockedEitherWay(String otherUid) async {
    final mine = await _blocks.doc(Block.idFor(uid, otherUid)).get();
    if (mine.exists) return true;
    try {
      final theirs = await _blocks.doc(Block.idFor(otherUid, uid)).get();
      return theirs.exists;
    } on FirebaseException {
      // Reading someone else's block is denied by the rules, which is the
      // point: treat a refusal as "cannot proceed" rather than "no block".
      return true;
    }
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
    batch.set(_blocks.doc(Block.idFor(uid, targetUid)), {
      'blocker': uid,
      'blocked': targetUid,
      'username': username,
      'displayName': displayName,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Lift a block this user placed. The friendship is not restored — they
  /// would have to ask again.
  Future<void> unblockUser(String blockedUid) =>
      _blocks.doc(Block.idFor(uid, blockedUid)).delete();

  Stream<List<Friendship>> watchAll() {
    return _friendships
        .where('users', arrayContains: uid)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => Friendship.fromMap(d.id, d.data())).toList());
  }

  /// Handles starting with [prefix], alphabetical, excluding this user's own.
  /// Handles are the `usernames` doc ids, so this is a doc-id range query —
  /// no composite index needed.
  Future<List<String>> searchHandles(String prefix, {int limit = 8}) async {
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

    // Blocked people are not findable, in either direction: the blocker
    // should not see them, and they should not be able to find their way
    // back by handle.
    final kept = <String>[];
    for (final d in candidates) {
      final otherUid = d.data()['uid'] as String?;
      if (otherUid == null) continue;
      if (await _blockedEitherWay(otherUid)) continue;
      kept.add(d.id);
    }
    return kept;
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

  /// Send a friend request to whoever owns [handle]. Resolves the handle via the
  /// public usernames index; refuses self, missing handles, and duplicates.
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
      throw FriendException('No one found with the handle @$h.');
    }

    // Either direction. The message is deliberately the same as "not found":
    // telling someone they have been blocked is itself information.
    if (await _blockedEitherWay(targetUid)) {
      throw FriendException('No one found with the handle @$h.');
    }

    // Duplicate check via a query we're allowed to run (the same array-contains
    // shape as the stream) — NOT a direct get() on the pair doc. Reading a
    // not-yet-existent friendships doc is denied, because the participant read
    // rule dereferences resource.data.users on a null resource.
    final mine =
        await _friendships.where('users', arrayContains: uid).get();
    final existing = mine.docs
        .where((d) => (d.data()['users'] as List?)?.contains(targetUid) ?? false)
        .firstOrNull;
    if (existing != null) {
      throw FriendException(existing.data()['status'] == 'accepted'
          ? "You're already friends with @$h."
          : 'There’s already a pending request with @$h.');
    }

    final users = [uid, targetUid]..sort();
    await _friendships.doc(Friendship.pairId(uid, targetUid)).set({
      'users': users,
      'requestedBy': uid,
      'status': 'pending',
      'profiles': {
        uid: {'username': me.username, 'displayName': me.displayName},
        targetUid: {'username': h},
      },
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Accept an incoming request, writing this user's identity into the doc so
  /// the requester can see who they're now friends with.
  Future<void> accept(String pairId) async {
    final me = await _myIdentity();
    final other = pairId.split('__').firstWhere((u) => u != uid, orElse: () => '');
    if (other.isNotEmpty && await _blockedEitherWay(other)) {
      throw const FriendException('That request is no longer available.');
    }
    await _friendships.doc(pairId).update({
      'status': 'accepted',
      'acceptedAt': FieldValue.serverTimestamp(),
      'profiles.$uid': {'username': me.username, 'displayName': me.displayName},
    });
  }

  /// Decline an incoming request, cancel an outgoing one, or unfriend — all the
  /// same delete from a participant's side.
  Future<void> remove(String pairId) => _friendships.doc(pairId).delete();
}

/// Null on the local/offline backend or before a uid exists; friends require a
/// real Firestore user.
final friendsRepositoryProvider = Provider<FriendsRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (!ref.watch(firebaseReadyProvider) || uid == null) return null;
  return FriendsRepository(db: FirebaseFirestore.instance, uid: uid);
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

/// The people this user has blocked. Empty when there is no backend.
final blockedAccountsProvider = StreamProvider<List<Block>>((ref) {
  final repo = ref.watch(friendsRepositoryProvider);
  if (repo == null) return Stream.value(const <Block>[]);
  return repo.watchBlocked();
});

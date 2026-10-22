import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../friends/friends_repository.dart';
import '../friends/models/friendship.dart';

/// Their friends, mirrored under their own public profile.
///
/// `friendships` cannot answer "who are their friends": a rule asking
/// whether the reader is a friend of one of a document's two participants
/// would have to look up a path built from that document's own data, which a
/// list query cannot prove — so the whole query would fail rather than
/// return the rows it is allowed to. The mirror's path names the owner
/// instead, so the rule's lookup comes from the path.
///
/// Both halves are written and deleted together, by whichever party is
/// acting, in the same batch as the friendship itself. That is what keeps
/// "my half exists" equivalent to "both halves exist", which is what lets
/// [reconcileFriendMirror] be one query rather than one read per friend.

/// One half of the mirror: `publicProfiles/{ownerUid}/friends/{friendUid}`.
DocumentReference<Map<String, dynamic>> friendMirrorRef(
  FirebaseFirestore db,
  String ownerUid,
  String friendUid,
) => db
    .collection('publicProfiles')
    .doc(ownerUid)
    .collection('friends')
    .doc(friendUid);

/// Both halves for a pair, in no particular order.
List<DocumentReference<Map<String, dynamic>>> friendMirrorPair(
  FirebaseFirestore db,
  String a,
  String b,
) => [friendMirrorRef(db, a, b), friendMirrorRef(db, b, a)];

/// The only value a mirror entry carries. The rules refuse anything else:
/// the id is the friend's uid, and every name is read from that person's own
/// public profile, so nothing here can go stale or be forged.
Map<String, dynamic> friendMirrorEntry() => {
  'since': FieldValue.serverTimestamp(),
};

/// Add both halves of a pair to [batch].
void addFriendMirror(
  WriteBatch batch,
  FirebaseFirestore db,
  String a,
  String b,
) {
  for (final ref in friendMirrorPair(db, a, b)) {
    batch.set(ref, friendMirrorEntry());
  }
}

/// Remove both halves of a pair in [batch]. A half that was never written is
/// a no-op: the delete rule reads only the path, never the document, so
/// deleting what is not there is allowed and costs nothing.
void removeFriendMirror(
  WriteBatch batch,
  FirebaseFirestore db,
  String a,
  String b,
) {
  for (final ref in friendMirrorPair(db, a, b)) {
    batch.delete(ref);
  }
}

/// Write the halves that are missing for my accepted friendships.
///
/// Covers everything accepted before the mirror existed, and anything a
/// batch could not land because the app was killed or offline. Idempotent,
/// and one query rather than one read per friend: because both halves are
/// always written together, my own half missing means the pair is missing.
Future<void> reconcileFriendMirror(
  FirebaseFirestore db,
  String uid,
  List<Friendship> friendships,
) async {
  if (!friendships.any((f) => f.isAccepted)) return;
  final mine = await db
      .collection('publicProfiles')
      .doc(uid)
      .collection('friends')
      .get();
  final missing = missingMirrorHalves(
    uid: uid,
    friendships: friendships,
    have: {for (final d in mine.docs) d.id},
  );
  if (missing.isEmpty) return;
  final batch = db.batch();
  for (final other in missing) {
    addFriendMirror(batch, db, uid, other);
  }
  await batch.commit();
}

/// Which of my accepted friendships my own half of the mirror is missing.
///
/// Pure, so the rule can be tested without Firestore: accepted only (a
/// pending request is not a friendship), each pair once, and nothing that
/// is already there. Pending entries are never written, which is what keeps
/// a request invisible on a profile until it is answered.
List<String> missingMirrorHalves({
  required String uid,
  required List<Friendship> friendships,
  required Set<String> have,
}) {
  final out = <String>[];
  for (final f in friendships) {
    if (!f.isAccepted) continue;
    final other = f.otherUid(uid);
    if (other == uid || other.isEmpty) continue;
    if (have.contains(other) || out.contains(other)) continue;
    out.add(other);
  }
  return out;
}

/// The launch-time reconcile, as a callable so a test can stand in for it
/// and the caller decides when it runs. Does nothing without a backend.
final friendMirrorReconcileProvider = Provider<Future<void> Function()>((ref) {
  final repo = ref.watch(friendsRepositoryProvider);
  if (repo == null) return () async {};
  return () async {
    try {
      final friendships = await ref.read(friendshipsProvider.future);
      await reconcileFriendMirror(repo.db, repo.uid, friendships);
    } catch (e) {
      // Retried on the next launch; nothing on screen depends on it.
      debugPrint('SONDR friend mirror reconcile error: ${e.runtimeType}');
    }
  };
});

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import 'models/profile.dart';

/// Thrown when a requested handle is already claimed by someone else.
class HandleTakenException implements Exception {
  const HandleTakenException();
}

/// Reads and writes the user profile + the unique handle index.
class ProfileRepository {
  ProfileRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _profileDoc(String uid) =>
      _db.collection('users').doc(uid).collection('meta').doc('profile');

  Future<Profile?> fetch(String uid) async {
    final doc = await _profileDoc(uid).get();
    if (!doc.exists) return null;
    return Profile.fromMap(uid, doc.data()!);
  }

  /// Atomically reserve [handle] for [uid] and write the profile. The handle
  /// index (`usernames/{handle}`) and the profile doc are written in one
  /// transaction; if the handle is already taken the transaction aborts with
  /// [HandleTakenException], so two users can't claim the same handle.
  Future<Profile> claimHandle({
    required String uid,
    required String handle,
    String? displayName,
  }) async {
    final h = handle.trim().toLowerCase();
    final display =
        (displayName == null || displayName.trim().isEmpty) ? h : displayName.trim();
    final handleRef = _db.collection('usernames').doc(h);
    final profileRef = _profileDoc(uid);

    await _db.runTransaction((tx) async {
      final existing = await tx.get(handleRef);
      if (existing.exists) throw const HandleTakenException();
      tx.set(handleRef, {'uid': uid});
      tx.set(
        profileRef,
        {
          'username': h,
          'displayName': display,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });

    return Profile(uid: uid, username: h, displayName: display);
  }
}

/// Null until Firebase is ready (keeps tests and the local path clear of it).
final profileRepositoryProvider = Provider<ProfileRepository?>((ref) {
  if (!ref.watch(firebaseReadyProvider)) return null;
  return ProfileRepository(FirebaseFirestore.instance);
});

/// The signed-in user's profile (null if none claimed yet). Re-fetches when the
/// auth user changes; invalidate it after claiming a handle.
final currentProfileProvider = FutureProvider<Profile?>((ref) async {
  final uid = ref.watch(currentUidProvider);
  final repo = ref.watch(profileRepositoryProvider);
  ref.watch(authUserProvider); // refresh on sign in/out/link
  if (uid == null || repo == null) return null;
  return repo.fetch(uid);
});

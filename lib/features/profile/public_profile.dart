import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../auth/models/profile.dart';
import '../auth/profile_repository.dart';
import '../photos/local_first.dart';
import '../profile/profile_providers.dart';
import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';

/// What one person can see of another.
///
/// `users/{uid}/**` is owner-only, so nothing about another person is
/// readable from it — not their handle, not their hours. This is the
/// published copy: the handle, the display name, and whole hours, written by
/// its owner and readable by any signed-in user (see firestore.rules).
///
/// Whole hours because that is what the profile prints. Publishing the exact
/// second count would mean a write every time anything was logged, for a
/// figure nobody reads.
class PublicProfile {
  const PublicProfile({
    required this.uid,
    required this.handle,
    required this.displayName,
    required this.hours,
  });

  final String uid;
  final String handle;
  final String displayName;

  /// Lifetime hours across every task, rounded down.
  final int hours;

  /// What to show as a name: the display name, falling back to the handle.
  String get label => displayName.isNotEmpty ? displayName : '@$handle';

  /// The letter in the ring when there is no photo to put there.
  String get initial {
    for (final source in [displayName, handle]) {
      final trimmed = source.trim();
      if (trimmed.isNotEmpty) return trimmed.substring(0, 1).toUpperCase();
    }
    return '';
  }

  Map<String, dynamic> toMap() => {
    'handle': handle,
    'displayName': displayName,
    'hours': hours,
  };

  factory PublicProfile.fromMap(String uid, Map<String, dynamic> map) =>
      PublicProfile(
        uid: uid,
        handle: (map['handle'] as String?) ?? '',
        displayName: (map['displayName'] as String?) ?? '',
        hours: (map['hours'] as num?)?.toInt() ?? 0,
      );

  /// Whether the published copy would say anything new.
  bool sameAs(PublicProfile? other) =>
      other != null &&
      other.handle == handle &&
      other.displayName == displayName &&
      other.hours == hours;
}

/// Reads and writes `publicProfiles`.
class PublicProfilesRepository {
  PublicProfilesRepository({required this.db, required this.uid});

  final FirebaseFirestore db;
  final String uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      db.collection('publicProfiles');

  /// Someone's published profile, or null if they have never published one
  /// (an older build, or a guest who has not claimed a handle).
  Future<PublicProfile?> fetch(
    String ofUid, {
    Source source = Source.serverAndCache,
  }) async {
    final doc = await _col.doc(ofUid).get(GetOptions(source: source));
    final data = doc.data();
    if (data == null) return null;
    return PublicProfile.fromMap(ofUid, data);
  }

  /// Publish mine. Merged, so a field this build does not know about
  /// survives, and stamped so a stale copy can be told from a fresh one.
  Future<void> publish(PublicProfile profile) => _col.doc(uid).set({
    ...profile.toMap(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  /// The uids in someone's friend mirror. Readable only by them and their
  /// friends — a stranger is DENIED, which is the "friends only" answer, not
  /// an error to show.
  Future<List<String>> friendUids(
    String ofUid, {
    Source source = Source.serverAndCache,
  }) async {
    final snap = await _col
        .doc(ofUid)
        .collection('friends')
        .get(GetOptions(source: source));
    return [for (final d in snap.docs) d.id];
  }
}

/// Null on the local/offline backend or before a uid exists.
final publicProfilesRepositoryProvider =
    Provider<PublicProfilesRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (!ref.watch(firebaseReadyProvider) || uid == null) return null;
  return PublicProfilesRepository(db: FirebaseFirestore.instance, uid: uid);
});

/// Someone's published profile, read local-first so a profile opened twice
/// paints from the cache instead of waiting on the network.
final publicProfileProvider =
    FutureProvider.autoDispose.family<PublicProfile?, String>((ref, ofUid) {
  final repo = ref.watch(publicProfilesRepositoryProvider);
  if (repo == null) return Future.value(null);
  ref.keepAlive();
  return localFirst<PublicProfile?>(
    ref,
    read: (source) => repo.fetch(ofUid, source: source),
    isEmpty: (p) => p == null,
    same: (a, b) => a == null ? b == null : a.sameAs(b),
  );
});

/// Someone's friends, as uids. Empty rather than throwing when the read is
/// refused: not being allowed to see a friend list is an answer.
final friendUidsProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, ofUid) async {
  final repo = ref.watch(publicProfilesRepositoryProvider);
  if (repo == null) return const [];
  ref.keepAlive();
  try {
    return await localFirst<List<String>>(
      ref,
      read: (source) => repo.friendUids(ofUid, source: source),
      isEmpty: (list) => list.isEmpty,
      same: sameIds,
    );
  } on FirebaseException catch (e) {
    if (e.code != 'permission-denied') {
      debugPrint('SONDR friend mirror read error: ${e.code}');
    }
    return const [];
  }
});

/// What to publish, or null for "nothing worth a write".
///
/// Pure, because this is the whole of the debounce rule: no handle means
/// nothing can be published (the rules check the handle against the
/// usernames index, and a guest has not claimed one), and a copy that would
/// say exactly what the published one already says is not written. Callers
/// may therefore call this as often as they like.
PublicProfile? profileToPublish({
  required String uid,
  required Profile? profile,
  required List<Task> tasks,
  required PublicProfile? published,
}) {
  if (profile == null || profile.username.isEmpty) return null;
  final mine = PublicProfile(
    uid: uid,
    handle: profile.username,
    displayName: profile.displayName,
    hours: wholeHoursOf(tasks),
  );
  return mine.sameAs(published) ? null : mine;
}

/// Publish my profile if the published copy would say something new.
///
/// Called at launch, when the handle or name changes, when a session is
/// logged, when a milestone is crossed, and when the app goes to the
/// background — never per tick, because the guard below is what decides,
/// not the caller: an unchanged figure writes nothing.
///
/// The comparison is against the published copy itself, read from the cache,
/// so it survives a reinstall and needs nothing stored on the side.
Future<void> publishMyPublicProfile(Ref ref) async {
  final repo = ref.read(publicProfilesRepositoryProvider);
  if (repo == null) return;
  try {
    final profile = await ref.read(currentProfileProvider.future);
    // Tasks are the only source of logged time, and they may still be
    // loading at launch — a published 0 would be worse than publishing late.
    final tasks = await ref.read(tasksProvider.future);
    // Against what this process last published, then — only if that says
    // nothing — against the published copy in the cache, which survives a
    // relaunch and a reinstall and so needs nothing stored on the side.
    var mine = profileToPublish(
      uid: repo.uid,
      profile: profile,
      tasks: tasks,
      published: _lastPublished,
    );
    if (mine == null) return;
    mine = profileToPublish(
      uid: repo.uid,
      profile: profile,
      tasks: tasks,
      published: await repo.fetch(repo.uid, source: Source.cache),
    );
    if (mine == null) {
      _lastPublished = PublicProfile(
        uid: repo.uid,
        handle: profile!.username,
        displayName: profile.displayName,
        hours: wholeHoursOf(tasks),
      );
      return;
    }
    await repo.publish(mine);
    _lastPublished = mine;
  } catch (e) {
    // A profile nobody can see yet is not worth a visible failure.
    debugPrint('SONDR publish profile error: ${e.runtimeType}');
  }
}

/// The last copy this process published, so repeated calls cost nothing.
PublicProfile? _lastPublished;

/// Forget what this process published — for tests, which share an isolate.
@visibleForTesting
void resetPublishedProfileMemory() => _lastPublished = null;

/// Lifetime whole hours across every task, archived ones included: the same
/// figure [lifetimeDurationProvider] shows on my own Profile.
int wholeHoursOf(List<Task> tasks) =>
    tasks.fold<int>(0, (total, t) => total + t.totalSeconds) ~/ 3600;

/// Publishing as a callable, so a caller decides when it runs and a test can
/// stand in for it.
final publishPublicProfileProvider = Provider<Future<void> Function()>(
  (ref) => () => publishMyPublicProfile(ref),
);

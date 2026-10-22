import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../friends/friends_repository.dart';
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
    this.seconds,
    this.ringProgress = 0,
  });

  final String uid;
  final String handle;
  final String displayName;

  /// Lifetime hours across every task, rounded down.
  ///
  /// Kept because a build that predates [seconds] reads this and nothing
  /// else. Everything here floors it the same way, so the two never
  /// disagree about what to print.
  final int hours;

  /// The exact figure the hours are floored from.
  ///
  /// The published copy used to carry whole hours alone, so "19h 59m"
  /// reached another person's page as a flat 19 with no way to tell it
  /// from 19h 00m. The seconds are published now and floored where they
  /// are shown; an older document has none, and [hours] answers for it.
  final int? seconds;

  /// Whole hours, from the exact figure when there is one.
  int get wholeHours => seconds == null ? hours : seconds! ~/ 3600;

  /// How far through its current 20-hour band their nearest milestone is,
  /// 0..1 — the same figure the owner's own hero ring fills by, so the two
  /// rings mean the same thing. Friends see the fill; a stranger sees the
  /// bare track, because a stranger is not being shown what they are
  /// working on.
  ///
  /// Rounded to a hundredth: the ring is 128 across, so a finer figure
  /// would be a write nobody could see.
  final double ringProgress;

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
    if (seconds != null) 'seconds': seconds,
    'ringProgress': ringProgress,
  };

  factory PublicProfile.fromMap(String uid, Map<String, dynamic> map) =>
      PublicProfile(
        uid: uid,
        handle: (map['handle'] as String?) ?? '',
        displayName: (map['displayName'] as String?) ?? '',
        hours: (map['hours'] as num?)?.toInt() ?? 0,
        seconds: (map['seconds'] as num?)?.toInt(),
        ringProgress: ((map['ringProgress'] as num?)?.toDouble() ?? 0)
            .clamp(0.0, 1.0),
      );

  /// Whether the published copy would say anything new.
  bool sameAs(PublicProfile? other) =>
      other != null &&
      other.handle == handle &&
      other.displayName == displayName &&
      other.hours == hours &&
      other.seconds == seconds &&
      other.ringProgress == ringProgress;
}

/// Where a published profile is read back and written.
///
/// An interface because the one thing that went wrong here is invisible
/// without one: a cache read that throws instead of coming back empty. A
/// fake can throw; Firestore cannot be asked to in a unit test.
abstract interface class ProfilePublishTarget {
  String get uid;

  /// The published copy as this device last saw it, or null when there is
  /// none — including when the cache cannot answer.
  Future<PublicProfile?> publishedCopy();

  Future<void> publish(PublicProfile profile);
}

/// Reads and writes `publicProfiles`.
class PublicProfilesRepository implements ProfilePublishTarget {
  PublicProfilesRepository({required this.db, required this.uid});

  final FirebaseFirestore db;

  @override
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

  /// My published copy as this device last saw it.
  ///
  /// Null when there is none — and null, NOT an error, when the cache
  /// cannot answer. Firestore THROWS `unavailable` on a cache read for a
  /// document it does not hold, which is the case for every account that
  /// has never published; letting that escape is what kept them
  /// unpublished, because the failure looked like "nothing to do".
  @override
  Future<PublicProfile?> publishedCopy() async {
    try {
      return await fetch(uid, source: Source.cache);
    } catch (_) {
      return null;
    }
  }

  /// Publish mine. Merged, so a field this build does not know about
  /// survives, and stamped so a stale copy can be told from a fresh one.
  @override
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

/// How a friend mirror is read. A seam, so a test can watch the reads
/// happen — the thing that was wrong here is a read that never happened
/// again.
final friendMirrorReaderProvider =
    Provider<Future<List<String>> Function(String uid, Source source)?>((ref) {
  final repo = ref.watch(publicProfilesRepositoryProvider);
  if (repo == null) return null;
  return (uid, source) => repo.friendUids(uid, source: source);
});

/// Someone's friends, as uids. Empty rather than throwing when the read is
/// refused: not being allowed to see a friend list is an answer.
///
/// Re-read whenever any friendship of mine changes. A friend list is the one
/// thing on a profile that a friendship CREATES the right to see: before
/// they accept, the read is refused and the refusal is cached as an empty
/// list, and the acceptance that makes it readable is exactly the moment
/// nothing was asking again. Accepting, removing and blocking all move a
/// friendships document, so one watch covers all three.
final friendUidsProvider =
    FutureProvider.autoDispose.family<List<String>, String>((ref, ofUid) async {
  final read = ref.watch(friendMirrorReaderProvider);
  if (read == null) return const [];
  ref.watch(friendshipsProvider);
  ref.keepAlive();
  try {
    return await localFirst<List<String>>(
      ref,
      read: (source) => read(ofUid, source),
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
    seconds: lifetimeSecondsOf(tasks),
    ringProgress: ringProgressOf(tasks),
  );
  return mine.sameAs(published) ? null : mine;
}

/// Publish my profile if the published copy would say something new.
///
/// Called at launch, when the handle or name changes, when a session is
/// logged, when a milestone is crossed, and when the app goes to the
/// background — never per tick, because the guard is what decides, not the
/// caller: an unchanged figure writes nothing.
Future<void> publishMyPublicProfile(Ref ref) async {
  final repo = ref.read(publicProfilesRepositoryProvider);
  if (repo == null) return;
  try {
    final profile = await ref.read(currentProfileProvider.future);
    // Tasks are the only source of logged time, and they may still be
    // loading at launch — a published 0 would be worse than publishing late.
    final tasks = await ref.read(tasksProvider.future);
    await publishTo(repo, profile: profile, tasks: tasks);
  } catch (e) {
    // A profile nobody can see yet is not worth a visible failure.
    debugPrint('SONDR publish profile error: ${e.runtimeType}');
  }
}

/// The publish rule itself: compare, then write only if it would say
/// something new. Against what this process last published first, because
/// that costs nothing, then against the copy on the device.
///
/// A published copy that cannot be READ is treated as no copy at all. It is
/// not the same thing as a copy that already says this — and treating the
/// two alike is what left every account unpublished: a device with no
/// document has nothing to read, so the comparison threw, the write was
/// skipped, and the document stayed missing for good.
Future<void> publishTo(
  ProfilePublishTarget target, {
  required Profile? profile,
  required List<Task> tasks,
}) async {
  final mine = profileToPublish(
    uid: target.uid,
    profile: profile,
    tasks: tasks,
    published: _lastPublished,
  );
  if (mine == null) return;
  PublicProfile? published;
  try {
    published = await target.publishedCopy();
  } catch (_) {
    published = null;
  }
  final against = profileToPublish(
    uid: target.uid,
    profile: profile,
    tasks: tasks,
    published: published,
  );
  // Already published, word for word: remember it so the next call is free.
  if (against == null) {
    _lastPublished = mine;
    return;
  }
  await target.publish(against);
  _lastPublished = against;
}

/// The last copy this process published, so repeated calls cost nothing.
PublicProfile? _lastPublished;

/// Forget what this process published — for tests, which share an isolate.
@visibleForTesting
void resetPublishedProfileMemory() => _lastPublished = null;

/// Lifetime seconds across every task, archived ones included: the same
/// figure [lifetimeDurationProvider] sums on my own Profile.
int lifetimeSecondsOf(List<Task> tasks) =>
    tasks.fold<int>(0, (total, t) => total + t.totalSeconds);

/// And the whole hours it floors to, which is what is printed.
int wholeHoursOf(List<Task> tasks) => lifetimeSecondsOf(tasks) ~/ 3600;

/// How full the hero ring is: the active task furthest through its current
/// 20-hour band, 0..1.
///
/// The same rule [nextMilestoneProvider] uses for my own ring — a task at
/// 19h is nearly there whatever it has logged in total — so the ring on a
/// profile of somebody else means exactly what the ring on mine does.
/// Archived tasks are not candidates: you are not climbing toward a
/// milestone on a task you have put away. Rounded to a hundredth.
double ringProgressOf(List<Task> tasks) {
  var best = 0.0;
  for (final t in tasks) {
    if (t.archived) continue;
    if (t.milestoneProgress > best) best = t.milestoneProgress;
  }
  return (best.clamp(0.0, 1.0) * 100).roundToDouble() / 100;
}

/// Publishing as a callable, so a caller decides when it runs and a test can
/// stand in for it.
final publishPublicProfileProvider = Provider<Future<void> Function()>(
  (ref) => () => publishMyPublicProfile(ref),
);

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_foundation/shared_preferences_foundation.dart';

import '../timer/session_store.dart' show kSessionAppGroup;

/// Taking someone out of everything you have already written.
///
/// A post's `audience` is frozen when it is written, and so is a comment's.
/// Unfriending deletes the friendship but leaves the other person inside
/// every audience they were in, so they keep seeing your old posts and your
/// old comments. Blocking did the same. This removes them.
///
/// It runs on BOTH unfriend and block, deliberately. If only blocking pruned,
/// then "their old posts vanished" would be the tell that distinguishes a
/// block from an unfriend — and nothing else in the block design discloses
/// that: the block document is readable by its author alone and a refused
/// request reuses the "no one found" wording.
///
/// Nothing is restored on unblock. They were removed from things they could
/// previously see; putting them back would be the surprise.
class ContentPruner {
  ContentPruner({
    required this.uid,
    required this.audiences,
    required this.pending,
  });

  final String uid;
  final PrunableAudiences audiences;
  final PendingPrunes pending;

  /// Firestore's limit is 500 writes per batch; 450 leaves room to grow the
  /// per-document work without having to think about it again.
  static const int batchLimit = 450;

  /// Remove [targetUid] from everything this user has written.
  ///
  /// Records the target as pending FIRST, so a prune that dies with the app
  /// — or never reaches the server — is retried at the next launch. Cleared
  /// only once the server has acknowledged every batch.
  ///
  /// Idempotent by construction: `arrayRemove` of something already gone is
  /// a no-op, so a retry costs writes and changes nothing.
  Future<void> pruneMyContentFor(String targetUid) async {
    if (targetUid.isEmpty || targetUid == uid) return;
    await pending.add(targetUid);
    await _run(targetUid);
  }

  /// Retry whatever a previous run did not finish. Called at launch.
  ///
  /// Failures are swallowed: this is cleanup running behind a cold start,
  /// and the entry stays pending for the launch after this one.
  Future<void> runPending() async {
    for (final target in await pending.read()) {
      try {
        await _run(target);
      } catch (e) {
        debugPrint('SONDR prune retry failed for one target: ${e.runtimeType}');
      }
    }
  }

  Future<void> _run(String targetUid) async {
    final paths = await audiences.mine();
    for (var i = 0; i < paths.length; i += batchLimit) {
      // Each chunk resolves only when the server has it; an offline commit
      // never resolves at all, so the entry stays pending and the next
      // launch tries again.
      await audiences.removeFrom(paths.skip(i).take(batchLimit).toList(), targetUid);
    }
    await pending.remove(targetUid);
  }
}

/// The documents a prune touches, and how to take a uid out of them.
///
/// A seam, so the ordering and the chunking above can be tested without a
/// network, and so the Firestore below stays small enough to read.
abstract class PrunableAudiences {
  /// Paths of every document this user wrote that carries an audience.
  Future<List<String>> mine();

  /// Remove [targetUid] from the audience of each of [paths], atomically.
  /// Never called with more than [ContentPruner.batchLimit] paths.
  Future<void> removeFrom(List<String> paths, String targetUid);
}

/// The real one: this user's posts, and their comments wherever they are.
class FirestoreAudiences implements PrunableAudiences {
  FirestoreAudiences({required this.db, required this.uid});

  final FirebaseFirestore db;
  final String uid;

  @override
  Future<List<String>> mine() async {
    // The audience filter is not a nicety. The posts read rule grants on
    // `audience` alone, so a query constraining only authorUid is refused
    // outright rather than returning rows — which is what this did, in
    // production, for every prune since it shipped. The author is always in
    // their own audience (every create seeds it, and removeFrom below never
    // takes the author out), so nothing of theirs is hidden by it.
    final posts = await db
        .collection('posts')
        .where('authorUid', isEqualTo: uid)
        .where('audience', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .get();
    // A collection group, because a comment of mine lives under someone
    // else's post. The rules allow exactly this query and no wider one.
    final comments = await db
        .collectionGroup('comments')
        .where('authorUid', isEqualTo: uid)
        .get();
    return [
      for (final d in posts.docs) d.reference.path,
      for (final d in comments.docs) d.reference.path,
    ];
  }

  @override
  Future<void> removeFrom(List<String> paths, String targetUid) async {
    if (paths.isEmpty) return;
    final batch = db.batch();
    for (final path in paths) {
      // arrayRemove, never a read-modify-write: removing something already
      // gone is a no-op, which is what makes a retry free of consequence.
      batch.update(db.doc(path), {
        'audience': FieldValue.arrayRemove([targetUid]),
      });
    }
    await batch.commit();
  }
}

/// The uids whose prune has not been confirmed by the server yet.
///
/// Small, local and durable: a handful of uids at most, written before the
/// work starts and cleared after it is acknowledged.
abstract class PendingPrunes {
  Future<List<String>> read();
  Future<void> add(String uid);
  Future<void> remove(String uid);
}

/// [PendingPrunes] in the App Group container, beside the running session.
///
/// Same suite and the same async API as the session store, so there is one
/// place on the device where this app keeps state that has to outlive a
/// process.
class PrefsPendingPrunes implements PendingPrunes {
  PrefsPendingPrunes({SharedPreferencesAsync? prefs})
    : _prefs =
          prefs ??
          SharedPreferencesAsync(
            options: SharedPreferencesAsyncFoundationOptions(
              suiteName: kSessionAppGroup,
            ),
          );

  static const String key = 'sondr.pendingPrunes';

  final SharedPreferencesAsync _prefs;

  @override
  Future<List<String>> read() async {
    try {
      return await _prefs.getStringList(key) ?? const [];
    } catch (e) {
      debugPrint('SONDR pending prunes read error: ${e.runtimeType}');
      return const [];
    }
  }

  @override
  Future<void> add(String uid) async {
    final now = await read();
    if (now.contains(uid)) return;
    await _write([...now, uid]);
  }

  @override
  Future<void> remove(String uid) async {
    final now = await read();
    if (!now.contains(uid)) return;
    await _write([for (final u in now) if (u != uid) u]);
  }

  Future<void> _write(List<String> uids) async {
    try {
      await _prefs.setStringList(key, uids);
    } catch (e) {
      debugPrint('SONDR pending prunes write error: ${e.runtimeType}');
    }
  }
}

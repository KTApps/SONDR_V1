import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../profile/public_profile.dart';
import 'friends_repository.dart';

/// Letting a new friend into what was posted before they were one.
///
/// A post's audience is frozen when it is shared, and until now it only
/// ever narrowed (a block, an unfriend — see content_prune.dart). So a
/// friend accepted today saw nothing from yesterday. This is the other
/// direction: for each of MY posts, add whoever is missing; then set each
/// of MY comments' audience to its post's, which is the one widening the
/// rules allow a comment. Posts first, comments second — a comment may
/// only follow a post that has already let the person in.
///
/// Idempotent: arrayUnion adds nothing twice, and a comment already equal
/// to its post is skipped. Batched under Firestore's limit. Never adds
/// anyone this user has blocked.
class AudienceWidener {
  AudienceWidener({
    required this.uid,
    required this.audiences,
    required this.blocked,
  });

  final String uid;
  final WidenableAudiences audiences;

  /// Whom this user has blocked — never let back in by this path.
  final Future<Set<String>> Function() blocked;

  static const int batchLimit = 450;

  /// Let [others] into everything of mine. The acceptor calls this for
  /// the person they accepted; the launch reconcile calls it with every
  /// friend the mirror names.
  Future<void> widenFor(Set<String> others) async {
    try {
      await _widen(others);
    } catch (e) {
      // Nothing on screen depends on it; the launch reconcile retries.
      debugPrint('SONDR audience widen error: ${e.runtimeType}');
    }
  }

  Future<void> _widen(Set<String> others) async {
    final blocks = await blocked();
    final people = {
      for (final o in others)
        if (o.isNotEmpty && o != uid && !blocks.contains(o)) o,
    };
    if (people.isEmpty) return;

    // Posts: add whoever is missing from each.
    final posts = await audiences.myPosts();
    final postUpdates = <(String path, List<String> add)>[];
    for (final p in posts) {
      final missing = [for (final o in people) if (!p.audience.contains(o)) o];
      if (missing.isNotEmpty) postUpdates.add((p.path, missing));
    }
    for (var i = 0; i < postUpdates.length; i += batchLimit) {
      await audiences.addToPosts(postUpdates.skip(i).take(batchLimit).toList());
    }

    // Comments: each follows its post, exactly.
    final comments = await audiences.myComments();
    final postAudience = <String, List<String>>{};
    final commentUpdates = <(String path, List<String> audience)>[];
    for (final c in comments) {
      final target = postAudience[c.postPath] ??=
          await audiences.audienceOf(c.postPath);
      if (!_sameSet(target, c.audience)) {
        commentUpdates.add((c.path, target));
      }
    }
    for (var i = 0; i < commentUpdates.length; i += batchLimit) {
      await audiences.setComments(commentUpdates.skip(i).take(batchLimit).toList());
    }
  }

  static bool _sameSet(List<String> a, List<String> b) =>
      a.length == b.length && a.toSet().containsAll(b);
}

/// One of my posts, and whom it reaches.
@immutable
class OwnPost {
  const OwnPost({required this.path, required this.audience});
  final String path;
  final List<String> audience;
}

/// One of my comments, whom it reaches, and the post it sits under.
@immutable
class OwnComment {
  const OwnComment({
    required this.path,
    required this.postPath,
    required this.audience,
  });
  final String path;
  final String postPath;
  final List<String> audience;
}

abstract class WidenableAudiences {
  Future<List<OwnPost>> myPosts();
  Future<List<OwnComment>> myComments();

  /// The post's audience as it stands now.
  Future<List<String>> audienceOf(String postPath);

  /// arrayUnion each post's additions. Never more than
  /// [AudienceWidener.batchLimit] at once.
  Future<void> addToPosts(List<(String path, List<String> add)> updates);

  /// Set each comment's audience outright.
  Future<void> setComments(List<(String path, List<String> audience)> updates);
}

class FirestoreWidenableAudiences implements WidenableAudiences {
  FirestoreWidenableAudiences({required this.db, required this.uid});

  final FirebaseFirestore db;
  final String uid;

  @override
  Future<List<OwnPost>> myPosts() async {
    // The same query the pruner uses, which the rules can prove.
    final snap = await db
        .collection('posts')
        .where('authorUid', isEqualTo: uid)
        .where('audience', arrayContains: uid)
        .orderBy('createdAt', descending: true)
        .get();
    return [
      for (final d in snap.docs)
        OwnPost(
          path: d.reference.path,
          audience: [for (final u in (d.data()['audience'] as List? ?? const [])) '$u'],
        ),
    ];
  }

  @override
  Future<List<OwnComment>> myComments() async {
    final snap = await db
        .collectionGroup('comments')
        .where('authorUid', isEqualTo: uid)
        .get();
    return [
      for (final d in snap.docs)
        OwnComment(
          path: d.reference.path,
          postPath: d.reference.parent.parent!.path,
          audience: [for (final u in (d.data()['audience'] as List? ?? const [])) '$u'],
        ),
    ];
  }

  @override
  Future<List<String>> audienceOf(String postPath) async {
    final doc = await db.doc(postPath).get();
    return [for (final u in (doc.data()?['audience'] as List? ?? const [])) '$u'];
  }

  @override
  Future<void> addToPosts(List<(String, List<String>)> updates) async {
    if (updates.isEmpty) return;
    final batch = db.batch();
    for (final (path, add) in updates) {
      batch.update(db.doc(path), {'audience': FieldValue.arrayUnion(add)});
    }
    await batch.commit();
  }

  @override
  Future<void> setComments(List<(String, List<String>)> updates) async {
    if (updates.isEmpty) return;
    final batch = db.batch();
    for (final (path, audience) in updates) {
      batch.update(db.doc(path), {'audience': audience});
    }
    await batch.commit();
  }
}

/// The launch-time reconcile: everyone the friend mirror names is let into
/// everything of mine. Silent on failure — retried next launch, and nothing
/// on screen depends on it.
final audienceReconcileProvider = Provider<Future<void> Function()>((ref) {
  final friends = ref.watch(friendsRepositoryProvider);
  final profiles = ref.watch(publicProfilesRepositoryProvider);
  final uid = ref.watch(currentUidProvider);
  if (friends == null || profiles == null || uid == null) return () async {};
  return () async {
    try {
      final mine = await profiles.friendUids(uid);
      await friends.widener.widenFor(mine.toSet());
    } catch (e) {
      debugPrint('SONDR audience reconcile error: ${e.runtimeType}');
    }
  };
});

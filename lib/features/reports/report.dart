import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';

/// Telling us about something.
///
/// A report is a message to us and nothing else: the app writes one and
/// never reads it back (see firestore.rules). What the reporter stops
/// seeing is a separate, private thing — see [HiddenThings] — so that
/// hiding keeps working offline and a report that fails hides nothing.
enum ReportTarget {
  post,
  comment,
  user;

  String get wire => name;
}

/// Why. Five answers, because a free-text box is a field nobody reads and
/// a place to put abuse.
enum ReportReason {
  spam('spam', 'Spam'),
  sexual('sexual', 'Nudity or sexual content'),
  hate('hate', 'Hate or harassment'),
  violence('violence', 'Violence'),
  other('other', 'Something else');

  const ReportReason(this.wire, this.label);

  final String wire;
  final String label;
}

/// Where the thing is. A post is its id; a comment is its post and its own
/// id, because that is where a moderator has to look; a person is their
/// uid.
String reportTargetKey({
  required ReportTarget type,
  required String id,
  String? postId,
}) => type == ReportTarget.comment ? '$postId/$id' : id;

/// The report's document id, which is what stops the same person telling
/// us the same thing twice: the rules refuse the second create.
///
/// A slash cannot be in a document id, so a comment's key swaps it for an
/// underscore here. The key itself keeps the readable form.
String reportId({
  required String reporterUid,
  required ReportTarget type,
  required String targetKey,
}) => '${reporterUid}__${type.wire}__${targetKey.replaceAll('/', '_')}';

/// The key a hidden thing is filed under, in the reporter's own document.
String hiddenKey(ReportTarget type, String targetKey) =>
    '${type.wire}__${targetKey.replaceAll('/', '_')}';

/// Sending a report, and hiding what it was about. A seam, so the sheets
/// and their tests never reach Firestore.
abstract interface class Reports {
  /// Returns true when we have the report — including when we already had
  /// it. Telling us twice is not a failure from where the reporter
  /// stands.
  Future<bool> send({
    required ReportTarget type,
    required String targetKey,
    required String targetOwnerUid,
    required ReportReason reason,
  });

  /// Take it out of this reader's own view. A person is never hidden —
  /// blocking is what does that, and it is a different decision.
  Future<void> hide(ReportTarget type, String targetKey);
}

class _FirestoreReports implements Reports {
  _FirestoreReports({required this.db, required this.uid});

  final FirebaseFirestore db;
  final String uid;

  @override
  Future<bool> send({
    required ReportTarget type,
    required String targetKey,
    required String targetOwnerUid,
    required ReportReason reason,
  }) async {
    final id = reportId(reporterUid: uid, type: type, targetKey: targetKey);
    try {
      await db.collection('reports').doc(id).set({
        'reporterUid': uid,
        'targetType': type.wire,
        'targetKey': targetKey,
        'targetOwnerUid': targetOwnerUid,
        'reason': reason.wire,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } on FirebaseException catch (e) {
      // The id already exists, so the create was refused: we have this
      // report. Nothing else about a refusal is the reporter's problem.
      if (e.code == 'permission-denied') return true;
      debugPrint('SONDR report error: ${e.code}');
      return false;
    }
  }

  @override
  Future<void> hide(ReportTarget type, String targetKey) async {
    if (type == ReportTarget.user) return;
    await db
        .collection('users')
        .doc(uid)
        .collection('hidden')
        .doc(hiddenKey(type, targetKey))
        .set({'hiddenAt': FieldValue.serverTimestamp()});
  }
}

/// Null on the local/offline backend or before a uid exists.
final reportsProvider = Provider<Reports?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (!ref.watch(firebaseReadyProvider) || uid == null) return null;
  return _FirestoreReports(db: FirebaseFirestore.instance, uid: uid);
});

/// What this reader has hidden, live, so a reported post leaves the screen
/// as the report lands rather than at the next launch.
final hiddenThingsProvider = StreamProvider<Set<String>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (!ref.watch(firebaseReadyProvider) || uid == null) {
    return Stream.value(const <String>{});
  }
  return FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .collection('hidden')
      .snapshots()
      .map((snap) => {for (final d in snap.docs) d.id});
});

/// The hidden set as a plain value, empty while it loads or if it fails.
///
/// FAILS OPEN, like the blocked set: a hidden list that cannot be read
/// shows one post too many, where treating the failure as "everything is
/// hidden" would blank the feed.
final hiddenKeysProvider = Provider<Set<String>>(
  (ref) => ref.watch(hiddenThingsProvider).maybeWhen(
    data: (keys) => keys,
    orElse: () => const <String>{},
  ),
);

/// Everything in [items] the reader has not hidden.
///
/// Pure, so the filter and its fail-open behaviour can be tested without
/// Firestore.
List<T> withoutHidden<T>(
  Iterable<T> items,
  Set<String> hidden,
  String Function(T) keyOf,
) => hidden.isEmpty
    ? items.toList()
    : [
        for (final item in items)
          if (!hidden.contains(keyOf(item))) item,
      ];

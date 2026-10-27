import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';

/// What happened, to whom, by whom.
///
/// In-app only: one document per event under the RECIPIENT, written by the
/// ACTOR in the same batch as the thing they did wherever there is a batch
/// to join. `notifications/{recipientUid}/items/{id}`. The rules allow an
/// actor only the kind of notice their action permits, and only to people
/// it concerns — a friend, the person asked, the one who asked, the one
/// who invited. Never to yourself.
enum NotificationType { request, accepted, like, comment, reply, milestone, invite }

@immutable
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.actorUid,
    required this.actorHandle,
    required this.at,
    this.postId,
    this.commentId,
    this.taskName,
    this.hours,
  });

  final String id;
  final NotificationType type;
  final String actorUid;
  final String actorHandle;

  /// Null only between the local write and the server stamp landing.
  final DateTime? at;
  final String? postId;
  final String? commentId;
  final String? taskName;
  final int? hours;

  static AppNotification? fromMap(String id, Map<String, dynamic> map) {
    final type = NotificationType.values
        .where((t) => t.name == map['type'])
        .firstOrNull;
    final actorUid = map['actorUid'];
    if (type == null || actorUid is! String) return null;
    DateTime? at;
    try {
      at = (map['at'] as dynamic)?.toDate() as DateTime?;
    } catch (_) {
      at = null;
    }
    return AppNotification(
      id: id,
      type: type,
      actorUid: actorUid,
      actorHandle: (map['actorHandle'] as String?) ?? '',
      at: at,
      postId: map['postId'] as String?,
      commentId: map['commentId'] as String?,
      taskName: map['taskName'] as String?,
      hours: map['hours'] is num ? (map['hours'] as num).toInt() : null,
    );
  }
}

/// Puts a notice into a batch. The repositories that act — friends, posts,
/// invites — each hold one, so the notice lands with the action or not at
/// all. A seam, so a test can see what would have been written.
abstract class NotificationsWriter {
  /// Add the write to [batch]. Does nothing when [recipientUid] is the
  /// actor, or empty: nothing to yourself, nothing to nobody.
  ///
  /// [id] names the document. A share retried after a crash writes its
  /// notices under the post's id, so a second attempt is refused by the
  /// rules — a notice never lands twice — rather than landing again.
  void add(
    WriteBatch batch, {
    required String recipientUid,
    required NotificationType type,
    required String actorHandle,
    String? postId,
    String? commentId,
    String? taskName,
    int? hours,
    String? id,
  });
}

class FirestoreNotificationsWriter implements NotificationsWriter {
  FirestoreNotificationsWriter({required this.db, required this.uid});

  final FirebaseFirestore db;
  final String uid;

  /// The document, exactly as the rules expect it: the keys for the kind,
  /// nothing more, and the server's clock.
  static Map<String, dynamic> document({
    required NotificationType type,
    required String actorUid,
    required String actorHandle,
    String? postId,
    String? commentId,
    String? taskName,
    int? hours,
  }) => {
    'type': type.name,
    'actorUid': actorUid,
    'actorHandle': actorHandle,
    'at': FieldValue.serverTimestamp(),
    'postId': ?postId,
    'commentId': ?commentId,
    'taskName': ?taskName,
    'hours': ?hours,
  };

  @override
  void add(
    WriteBatch batch, {
    required String recipientUid,
    required NotificationType type,
    required String actorHandle,
    String? postId,
    String? commentId,
    String? taskName,
    int? hours,
    String? id,
  }) {
    if (recipientUid.isEmpty || recipientUid == uid) return;
    final items = db.collection('notifications').doc(recipientUid).collection('items');
    final ref = id == null ? items.doc() : items.doc(id);
    batch.set(
      ref,
      document(
        type: type,
        actorUid: uid,
        actorHandle: actorHandle,
        postId: postId,
        commentId: commentId,
        taskName: taskName,
        hours: hours,
      ),
    );
  }
}

/// Nothing: no backend, or no account yet.
class NoNotificationsWriter implements NotificationsWriter {
  const NoNotificationsWriter();

  @override
  void add(
    WriteBatch batch, {
    required String recipientUid,
    required NotificationType type,
    required String actorHandle,
    String? postId,
    String? commentId,
    String? taskName,
    int? hours,
    String? id,
  }) {}
}

/// What has been written to me.
class NotificationsRepository {
  NotificationsRepository({required this.db, required this.uid});

  final FirebaseFirestore db;
  final String uid;

  static const int limit = 100;
  static const String seenAtField = 'notificationsSeenAt';

  CollectionReference<Map<String, dynamic>> get _items =>
      db.collection('notifications').doc(uid).collection('items');

  DocumentReference<Map<String, dynamic>> get _profile =>
      db.collection('users').doc(uid).collection('meta').doc('profile');

  /// The newest hundred, newest first.
  Stream<List<AppNotification>> watchMine() {
    return _items.orderBy('at', descending: true).limit(limit).snapshots().map(
      (snap) => [
        for (final d in snap.docs) ?AppNotification.fromMap(d.id, d.data()),
      ],
    );
  }

  /// When the page was last opened — nothing newer is "new".
  Stream<DateTime?> watchSeenAt() {
    return _profile.snapshots().map((d) {
      try {
        return (d.data()?[seenAtField] as dynamic)?.toDate() as DateTime?;
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> markSeen() async {
    try {
      await _profile.set({
        seenAtField: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('SONDR notifications seen error: ${e.runtimeType}');
    }
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (!ref.watch(firebaseReadyProvider) || uid == null) return null;
  return NotificationsRepository(db: FirebaseFirestore.instance, uid: uid);
});

/// Whether anything has arrived since the page was last opened.
///
/// Pure, so the dot is tested without a stream: any item newer than seenAt,
/// or any item at all when the page has never been opened.
bool hasUnread(List<AppNotification> items, DateTime? seenAt) {
  for (final n in items) {
    final at = n.at;
    if (at == null) continue;
    if (seenAt == null || at.isAfter(seenAt)) return true;
  }
  return false;
}

final myNotificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final repo = ref.watch(notificationsRepositoryProvider);
  if (repo == null) return Stream.value(const []);
  return repo.watchMine();
});

final notificationsSeenAtProvider = StreamProvider<DateTime?>((ref) {
  final repo = ref.watch(notificationsRepositoryProvider);
  if (repo == null) return Stream.value(null);
  return repo.watchSeenAt();
});

final hasUnreadNotificationsProvider = Provider<bool>((ref) {
  final items = ref.watch(myNotificationsProvider).value ?? const [];
  final seen = ref.watch(notificationsSeenAtProvider).value;
  return hasUnread(items, seen);
});

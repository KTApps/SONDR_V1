import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';

/// One credited session: when it began and how long it was.
///
/// The task document keeps time by DAY (`secondsByDay`), which is what the
/// calendar reads; a milestone story needs the sessions themselves — one
/// segment of effort per session, with the photo that was taken at its
/// end. This is that record, written once per credit, beside the credit.
///
/// Additive and forward-only: a task credited before the log existed has no
/// records, and the story falls back to days (see band_story.dart).
@immutable
class SessionRecord {
  const SessionRecord({
    required this.taskId,
    required this.at,
    required this.seconds,
  });

  final String taskId;

  /// When the session began, epoch milliseconds — the same instant the
  /// credit is keyed by (`Task.sessionKey`), so the log dedupes exactly as
  /// the credit does.
  final int at;
  final int seconds;

  /// One document per session, named so a retried credit rewrites the same
  /// record rather than adding a second.
  String get id => '${taskId}_$at';

  Map<String, dynamic> toMap() => {
    'taskId': taskId,
    'at': at,
    'seconds': seconds,
  };

  static SessionRecord? fromMap(Map<String, dynamic> map) {
    final taskId = map['taskId'];
    final at = map['at'];
    final seconds = map['seconds'];
    if (taskId is! String || at is! num || seconds is! num) return null;
    return SessionRecord(
      taskId: taskId,
      at: at.toInt(),
      seconds: seconds.toInt(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SessionRecord &&
      other.taskId == taskId &&
      other.at == at &&
      other.seconds == seconds;

  @override
  int get hashCode => Object.hash(taskId, at, seconds);
}

abstract interface class SessionLog {
  /// Write (or rewrite) the record. Never throws past the caller's credit:
  /// a session that was credited but not logged is a story with a day
  /// fallback, not lost time.
  Future<void> record(SessionRecord session);

  /// Every logged session of a task, oldest first.
  Future<List<SessionRecord>> forTask(String taskId);
}

/// Where there is no backend, or no account yet.
class NoSessionLog implements SessionLog {
  const NoSessionLog();

  @override
  Future<void> record(SessionRecord session) async {}

  @override
  Future<List<SessionRecord>> forTask(String taskId) async => const [];
}

/// `users/{uid}/sessions/{taskId}_{at}` — a subcollection of the user, not
/// of the task, on purpose: a client cannot discover a document's
/// subcollections, so the account cascade deletes by a fixed list of
/// `users/{uid}/<name>` (see account_cascade.dart), and a collection nested
/// under a task would be left behind when the account went. The owner-only
/// rule on `users/{uid}/**` covers it.
///
/// Read by task id alone and sorted here, so no composite index is needed.
class FirestoreSessionLog implements SessionLog {
  FirestoreSessionLog({required this.db, required this.uid});

  final FirebaseFirestore db;
  final String uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      db.collection('users').doc(uid).collection('sessions');

  @override
  Future<void> record(SessionRecord session) async {
    try {
      await _col.doc(session.id).set(session.toMap(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('SONDR session log error: ${e.runtimeType}');
    }
  }

  @override
  Future<List<SessionRecord>> forTask(String taskId) async {
    try {
      final snap = await _col.where('taskId', isEqualTo: taskId).get();
      final out = <SessionRecord>[];
      for (final d in snap.docs) {
        final r = SessionRecord.fromMap(d.data());
        if (r != null) out.add(r);
      }
      out.sort((a, b) => a.at.compareTo(b.at));
      return out;
    } catch (e) {
      debugPrint('SONDR session log read error: ${e.runtimeType}');
      return const [];
    }
  }
}

final sessionLogProvider = Provider<SessionLog>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (!ref.watch(firebaseReadyProvider) || uid == null) {
    return const NoSessionLog();
  }
  return FirestoreSessionLog(db: FirebaseFirestore.instance, uid: uid);
});

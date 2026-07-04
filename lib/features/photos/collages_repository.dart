import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import 'models/collage.dart';

/// The milestone collage store. Each collage is a document under
/// `users/{uid}/collages/{taskId}_{milestoneHours}` (secured by the Firestore
/// catch-all rule, like photos) holding photo *id* references — no binaries.
/// Firebase-only, mirroring [photosRepositoryProvider].
class CollagesRepository {
  CollagesRepository({required this.db, required this.uid});

  final FirebaseFirestore db;
  final String uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      db.collection('users').doc(uid).collection('collages');

  /// The collage for a task's milestone, or null if none composed yet.
  Future<Collage?> get(String taskId, int milestoneHours) async {
    final doc = await _col.doc(Collage.docId(taskId, milestoneHours)).get();
    final data = doc.data();
    if (data == null) return null;
    return Collage.fromMap(data);
  }

  /// Auto-compose save at the milestone moment. Idempotent and **non-destructive**:
  /// if a collage already exists and has been user-edited (`edited: true`), it is
  /// left untouched — a re-crossing or re-open never clobbers a curated collage.
  /// Otherwise (new, or a prior auto one) it's (re)written with the freshly
  /// composed [photoIds], preserving the original `createdAt`.
  Future<void> saveAuto(
    String taskId,
    int milestoneHours,
    List<String> photoIds,
  ) async {
    final ref = _col.doc(Collage.docId(taskId, milestoneHours));
    final existing = await ref.get();
    if (existing.data()?['edited'] == true) return; // don't clobber a curated one
    await ref.set({
      'taskId': taskId,
      'milestoneHours': milestoneHours,
      'photoIds': photoIds,
      'edited': false,
      'createdAt': existing.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
    });
  }
}

/// The collage store, or null on the local/offline backend or before a uid
/// exists — mirrors [photosRepositoryProvider].
final collagesRepositoryProvider = Provider<CollagesRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (!ref.watch(firebaseReadyProvider) || uid == null) return null;
  return CollagesRepository(db: FirebaseFirestore.instance, uid: uid);
});

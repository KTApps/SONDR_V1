import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import 'models/collage.dart';
import 'models/photo.dart';
import 'photos_repository.dart';

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

  /// Persist a user-curated collage: the kept [photoIds] with `edited: true`. No
  /// guard — an explicit edit always writes, and the `edited` flag then protects
  /// it from a later auto-compose ([saveAuto] bails on `edited:true`). Preserves
  /// the original `createdAt`.
  Future<void> saveEdited(
    String taskId,
    int milestoneHours,
    List<String> photoIds,
  ) async {
    final ref = _col.doc(Collage.docId(taskId, milestoneHours));
    final existing = await ref.get();
    await ref.set({
      'taskId': taskId,
      'milestoneHours': milestoneHours,
      'photoIds': photoIds,
      'edited': true,
      'createdAt': existing.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
    });
  }

  /// Every collage, newest first. Single-field `orderBy(createdAt)` → automatic
  /// index, no composite.
  Future<List<Collage>> allCollages() async {
    final snap = await _col.orderBy('createdAt', descending: true).get();
    return [for (final d in snap.docs) Collage.fromMap(d.data())];
  }
}

/// The collage store, or null on the local/offline backend or before a uid
/// exists — mirrors [photosRepositoryProvider].
final collagesRepositoryProvider = Provider<CollagesRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (!ref.watch(firebaseReadyProvider) || uid == null) return null;
  return CollagesRepository(db: FirebaseFirestore.instance, uid: uid);
});

/// The user's collages for display — newest first, and only those that actually
/// have photos (a zero-capture milestone composes an empty collage worth
/// nothing to browse). Empty on the local backend. Backs the profile Milestones
/// doorway and the collages screen.
final collagesListProvider =
    FutureProvider.autoDispose<List<Collage>>((ref) async {
  final repo = ref.watch(collagesRepositoryProvider);
  if (repo == null) return const [];
  final all = await repo.allCollages();
  return [for (final c in all) if (c.photoIds.isNotEmpty) c];
});

/// A collage's photos, resolved live from its ordered photo ids (keyed by the
/// ids joined with ',' — a stable value key). Missing photos are dropped, so a
/// deleted photo just vanishes from the grid. Empty on the local backend.
final collagePhotosProvider =
    FutureProvider.family.autoDispose<List<Photo>, String>((ref, idsCsv) async {
  final repo = ref.watch(photosRepositoryProvider);
  if (repo == null) return const [];
  final ids = [for (final s in idsCsv.split(',')) if (s.isNotEmpty) s];
  return repo.photosByIds(ids);
});

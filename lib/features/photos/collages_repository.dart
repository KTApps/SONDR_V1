import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import 'models/collage.dart';
import 'collage_selection.dart';
import 'local_first.dart';
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

  /// Remove every collage of [taskId]. Returns how many went.
  Future<int> deleteForTask(String taskId) async {
    final snap = await _col.where('taskId', isEqualTo: taskId).get();
    for (final d in snap.docs) {
      await d.reference.delete();
    }
    return snap.docs.length;
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

  /// Put the crossing photo into this milestone's stored collage, if there
  /// is one: recomposed from [band] when auto-composed, appended to the
  /// owner's picks when curated — see [attachCrossingIds]. No collage, no
  /// write: the stretch shows the band itself, which already holds it.
  Future<void> attachCrossing(
    String taskId,
    int milestoneHours,
    String crossingId,
    List<Photo> band,
  ) async {
    final ref = _col.doc(Collage.docId(taskId, milestoneHours));
    final existing = await ref.get();
    final data = existing.data();
    if (data == null) return;
    final collage = Collage.fromMap(data);
    final ids = attachCrossingIds(collage, band, crossingId);
    if (ids.length == collage.photoIds.length && collage.edited) return;
    await ref.set({
      'taskId': taskId,
      'milestoneHours': milestoneHours,
      'photoIds': ids,
      'edited': collage.edited,
      'createdAt': data['createdAt'] ?? FieldValue.serverTimestamp(),
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
  Future<List<Collage>> allCollages() => allCollagesFrom();

  /// [allCollages], read from [source].
  Future<List<Collage>> allCollagesFrom({
    Source source = Source.serverAndCache,
  }) async {
    final snap = await _col
        .orderBy('createdAt', descending: true)
        .get(GetOptions(source: source));
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
  // Kept once fetched: refreshed explicitly by invalidatePhotoViews on every
  // write, so a disposal would catch nothing — only cost a re-fetch, and an
  // empty first frame, on every open.
  ref.keepAlive();
  final repo = ref.watch(collagesRepositoryProvider);
  if (repo == null) return const [];
  final all = await localFirst<List<Collage>>(
    ref,
    read: (source) => repo.allCollagesFrom(source: source),
    isEmpty: (v) => v.isEmpty,
    same: (a, b) => sameIds(
      [for (final c in a) '${c.id}:${c.photoIds.join(',')}'],
      [for (final c in b) '${c.id}:${c.photoIds.join(',')}'],
    ),
  );
  return [for (final c in all) if (c.photoIds.isNotEmpty) c];
});

/// A collage's photos, resolved live from its ordered photo ids (keyed by the
/// ids joined with ',' — a stable value key). Missing photos are dropped, so a
/// deleted photo just vanishes from the grid. Empty on the local backend.
final collagePhotosProvider =
    FutureProvider.family.autoDispose<List<Photo>, String>((ref, idsCsv) async {
  // Kept once fetched: refreshed explicitly by invalidatePhotoViews on every
  // write, so a disposal would catch nothing — only cost a re-fetch, and an
  // empty first frame, on every open.
  ref.keepAlive();
  final repo = ref.watch(photosRepositoryProvider);
  if (repo == null) return const [];
  final ids = [for (final s in idsCsv.split(',')) if (s.isNotEmpty) s];
  return localFirst<List<Photo>>(
    ref,
    read: (source) => repo.photosByIdsFrom(ids, source: source),
    isEmpty: (v) => v.isEmpty,
    same: (a, b) => sameIds([for (final p in a) p.id], [for (final p in b) p.id]),
  );
});

/// Every photo in one task's milestone band, chronological and uncapped —
/// the stretch itself, before any curation. Keyed "taskId|hours" rather than
/// a record so the family key is a plain stable value, matching
/// [collagePhotosProvider]'s csv key.
///
/// A band with no stored [Collage] still has photos; this is what the journey
/// shows for it.
final bandPhotosProvider =
    FutureProvider.family.autoDispose<List<Photo>, String>((ref, key) async {
  // Kept once fetched: refreshed explicitly by invalidatePhotoViews on every
  // write, so a disposal would catch nothing — only cost a re-fetch, and an
  // empty first frame, on every open.
  ref.keepAlive();
  final repo = ref.watch(photosRepositoryProvider);
  if (repo == null) return const [];
  final parts = key.split('|');
  if (parts.length != 2) return const [];
  final hours = int.tryParse(parts[1]);
  if (hours == null) return const [];
  return localFirst<List<Photo>>(
    ref,
    read: (source) => repo.photosForBandFrom(parts[0], hours, source: source),
    isEmpty: (v) => v.isEmpty,
    same: (a, b) => sameIds([for (final p in a) p.id], [for (final p in b) p.id]),
  );
});

/// Every photo a task has that belongs to a REACHED band, newest band first.
/// Backs the task row's photo count and its representative thumbnail.
/// Photos with a null cumulativeSeconds are unassignable and excluded, the
/// same rule the bands themselves use.
final taskBandPhotosProvider =
    FutureProvider.family.autoDispose<List<Photo>, String>((ref, taskId) async {
  // Kept once fetched: refreshed explicitly by invalidatePhotoViews on every
  // write, so a disposal would catch nothing — only cost a re-fetch, and an
  // empty first frame, on every open.
  ref.keepAlive();
  final repo = ref.watch(photosRepositoryProvider);
  if (repo == null) return const [];
  final all = await localFirst<List<Photo>>(
    ref,
    read: (source) => repo.photosForTaskFrom(taskId, source: source),
    isEmpty: (v) => v.isEmpty,
    same: (a, b) => sameIds([for (final p in a) p.id], [for (final p in b) p.id]),
  );
  final assignable = [
    for (final p in all)
      if (p.cumulativeSeconds != null) p,
  ]..sort((a, b) => b.cumulativeSeconds!.compareTo(a.cumulativeSeconds!));
  return assignable;
});

/// Everything one stretch shows, resolved together: its stored collage (if
/// any) and the photos to draw — the collage's, with the crossing photo
/// added back, or the band itself.
class BandDetail {
  const BandDetail({required this.collage, required this.photos});
  final Collage? collage;
  final List<Photo> photos;
}

/// One answer for one stretch — the band detail draws from THIS and nothing
/// else. Keyed "taskId|hours". It awaits the collage list, the band and the
/// collage's own photos before answering, so the grid is built once, with
/// the crossing photo already in it. Drawing from the three underneath as
/// they landed built the grid twice, and the second time with a different
/// column count.
final bandDetailProvider =
    FutureProvider.family.autoDispose<BandDetail, String>((ref, key) async {
  ref.keepAlive(); // refreshed by invalidatePhotoViews, never disposed
  final parts = key.split('|');
  if (parts.length != 2) return const BandDetail(collage: null, photos: []);
  final taskId = parts[0];
  final hours = int.tryParse(parts[1]);
  if (hours == null) return const BandDetail(collage: null, photos: []);
  final collages = await ref.watch(collagesListProvider.future);
  final collage = collages
      .where((c) => c.taskId == taskId && c.milestoneHours == hours)
      .firstOrNull;
  final band = await ref.watch(bandPhotosProvider(key).future);
  if (collage == null) return BandDetail(collage: null, photos: band);
  final shown =
      await ref.watch(collagePhotosProvider(collage.photoIds.join(',')).future);
  return BandDetail(
    collage: collage,
    photos: withCrossingPhotos(shown, band, hours),
  );
});

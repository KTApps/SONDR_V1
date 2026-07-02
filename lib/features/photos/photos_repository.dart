import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import 'models/photo.dart';

/// The private photo store. Each photo is a document under
/// `users/{uid}/photos/{photoId}` (secured by the Firestore catch-all rule) with
/// its binary at `users/{uid}/photos/{photoId}.jpg` in Storage. Private-first:
/// later surfaces (calendar, day-detail, feed) read *from* here.
///
/// Firebase-only — like [postsRepositoryProvider] there's no local backend
/// (capture needs a network upload anyway), so the provider is null off Firebase.
class PhotosRepository {
  PhotosRepository({required this.db, required this.uid});

  final FirebaseFirestore db;
  final String uid;

  CollectionReference<Map<String, dynamic>> get _col =>
      db.collection('users').doc(uid).collection('photos');

  /// Upload a captured photo's binary to the user's own photo space, keyed by
  /// [photoId] (the deterministic `{taskId}_{timestamp}`). Reuses the milestone
  /// upload pattern (putFile + jpeg metadata + download URL). Returns both the
  /// URL and the Storage path so the caller can persist them on the doc — the
  /// path is retained so [delete] can later remove the binary.
  Future<({String url, String storagePath})> uploadPhoto(
    File file, {
    required String photoId,
  }) async {
    final path = 'users/$uid/photos/$photoId.jpg';
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    return (url: url, storagePath: path);
  }

  /// Write (or overwrite) the photo document at its deterministic id. Idempotent:
  /// re-saving the same `{taskId}_{timestamp}` replaces rather than duplicates.
  Future<void> savePhoto(Photo photo) => _col.doc(photo.id).set(photo.toMap());

  /// All photos captured on [dayKey], newest first. A single equality filter, so
  /// no composite index is needed; sorted client-side by [Photo.timestamp]
  /// (a day holds few photos). Backing query for the calendar and day-detail.
  Future<List<Photo>> photosForDay(String dayKey) async {
    final snap = await _col.where('dayKey', isEqualTo: dayKey).get();
    final photos = [for (final d in snap.docs) Photo.fromMap(d.data())];
    photos.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return photos;
  }

  /// Remove a photo entirely — both the Firestore doc and its Storage binary.
  /// The doc is deleted first so the photo disappears from every surface at
  /// once; the binary is then deleted best-effort (a missing object is fine). If
  /// the binary delete fails we orphan an invisible file rather than leave a doc
  /// pointing at a deleted image.
  Future<void> delete(Photo photo) async {
    await _col.doc(photo.id).delete();
    try {
      await FirebaseStorage.instance.ref(photo.storagePath).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }
}

/// The private photo store, or null on the local/offline backend or before a uid
/// exists — mirrors [postsRepositoryProvider].
final photosRepositoryProvider = Provider<PhotosRepository?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (!ref.watch(firebaseReadyProvider) || uid == null) return null;
  return PhotosRepository(db: FirebaseFirestore.instance, uid: uid);
});

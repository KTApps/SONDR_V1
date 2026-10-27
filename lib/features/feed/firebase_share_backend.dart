
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/backend.dart';
import '../notifications/notifications_repository.dart';
import '../photos/collages_repository.dart';
import '../photos/models/photo.dart';
import '../photos/photo_refresh.dart';
import '../photos/photos_repository.dart';
import 'models/post.dart';
import 'posts_repository.dart';
import 'share_job.dart';
import 'share_trace.dart';

/// The share job's backend on Firebase: Storage by named path, Firestore
/// by id, the notices under the post's id so a rerun cannot land twice.
class FirebaseShareBackend implements ShareBackend {
  FirebaseShareBackend({
    required this.db,
    required this.storage,
    required this.uid,
    required this.posts,
    required this.photos,
    required this.collages,
    required this.notifier,
  });

  final FirebaseFirestore db;
  final FirebaseStorage storage;
  @override
  final String uid;
  final PostsRepository posts;
  final PhotosRepository photos;
  final CollagesRepository collages;
  final NotificationsWriter notifier;

  CollectionReference<Map<String, dynamic>> get _posts => db.collection('posts');

  @override
  String newPostId() => posts.newPostId();

  /// The post's createdAt is the client's clock as a Timestamp, not a
  /// number: Firestore orders numbers before timestamps, and the feed is
  /// ordered by createdAt — a number would put the new post at the end.
  @override
  Future<void> setPendingPost(String postId, Map<String, dynamic> doc) {
    final createdAt = doc['createdAt'];
    return _posts.doc(postId).set({
      ...doc,
      if (createdAt is int) 'createdAt': Timestamp.fromMillisecondsSinceEpoch(createdAt),
    });
  }

  @override
  Future<String> upload(String path, Uint8List bytes) async {
    final ref = storage.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
    return ref.getDownloadURL();
  }

  @override
  Future<Uint8List> download(String storagePath) => posts.photoBytes(storagePath);

  @override
  Future<void> savePhoto(Photo photo) => photos.savePhoto(photo);

  @override
  Future<void> attachCrossing(String taskId, int milestoneHours, String photoId) async {
    final band = await photos.photosForBand(taskId, milestoneHours);
    await collages.attachCrossing(taskId, milestoneHours, photoId, band);
  }

  @override
  Future<PostAuthor> author() => posts.author();

  @override
  Future<List<String>> audience() => posts.audience();

  @override
  Future<void> finishPost(String postId, Map<String, dynamic> update) =>
      _posts.doc(postId).update(update);

  /// One batch, every notice under the post's id. The rules allow a notice
  /// to be created and never updated, so a rerun of a batch that already
  /// landed is refused as a whole — which is the proof it landed, and is
  /// taken as done.
  @override
  Future<void> notify(ShareJob job, List<String> friends, PostAuthor author) async {
    final batch = db.batch();
    for (final u in friends) {
      notifier.add(
        batch,
        recipientUid: u,
        type: NotificationType.milestone,
        actorHandle: author.username,
        postId: job.postId,
        taskName: job.taskName,
        hours: job.milestoneHours,
        id: job.postId,
      );
    }
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      debugPrint('SONDR milestone notices already sent for ${job.postId}');
    }
  }

  @override
  Future<void> setCover(String taskId, int milestoneHours, {String? coverUrl, String? thumbUrl}) =>
      collages.setCover(taskId, milestoneHours, coverUrl: coverUrl, thumbUrl: thumbUrl);

  @override
  Future<void> markShared(List<String> photoIds) => photos.markShared(photoIds);

  @override
  Future<void> deleteFiles(List<String> paths) async {
    for (final path in paths) {
      try {
        await storage.ref(path).delete();
      } on FirebaseException catch (e) {
        if (e.code != 'object-not-found') rethrow;
      }
    }
  }
}

/// Bytes the image cache already holds for [url], or null: a band photo
/// the strips have shown need not be fetched again to be re-uploaded.
Future<Uint8List?> cachedBytesOf(String url) async {
  try {
    final info = await DefaultCacheManager().getFileFromCache(url);
    if (info == null) return null;
    return info.file.readAsBytes();
  } catch (_) {
    return null;
  }
}

final shareBackendProvider = Provider<ShareBackend?>((ref) {
  final uid = ref.watch(currentUidProvider);
  final posts = ref.watch(postsRepositoryProvider);
  final photos = ref.watch(photosRepositoryProvider);
  final collages = ref.watch(collagesRepositoryProvider);
  if (!ref.watch(firebaseReadyProvider) || uid == null || posts == null || photos == null || collages == null) {
    return null;
  }
  return FirebaseShareBackend(
    db: FirebaseFirestore.instance,
    storage: FirebaseStorage.instance,
    uid: uid,
    posts: posts,
    photos: photos,
    collages: collages,
    notifier: posts.notifier,
  );
});

/// The runner, once there is someone to share as. Null on the local
/// backend. One per account, kept for the app's life, so a job carries on
/// across screens.
final shareJobRunnerProvider = Provider<ShareJobRunner?>((ref) {
  final backend = ref.watch(shareBackendProvider);
  if (backend == null) return null;
  return ShareJobRunner(
    store: ref.watch(shareJobStoreProvider),
    backend: backend,
    cached: cachedBytesOf,
    onTrace: (t) => ref.read(lastShareTraceProvider.notifier).set(t),
    onPrivateSaved: () => invalidatePhotoViewsWith(ref),
  );
});

/// What the cards watch: a job's state by post id, null when there is no
/// job for it.
final shareJobStateProvider = Provider.family<ShareJobState?, String>((ref, postId) {
  return ref.watch(_shareStatesProvider)[postId];
});

final _shareStatesProvider = Provider<Map<String, ShareJobState>>((ref) {
  final runner = ref.watch(shareJobRunnerProvider);
  if (runner == null) return const {};
  void listener() => ref.invalidateSelf();
  runner.states.addListener(listener);
  ref.onDispose(() => runner.states.removeListener(listener));
  return runner.states.value;
});

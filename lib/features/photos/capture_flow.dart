import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date.dart';
import '../feed/models/post.dart';
import '../feed/posts_repository.dart';
import '../shell/main_shell.dart';
import 'capture_review_screen.dart';
import 'models/photo.dart';
import 'photo_refresh.dart';
import 'photos_repository.dart';
import 'sondr_camera.dart';

/// The whole posting journey: camera → review → keep or share.
///
/// One loop, because "retake" is the only thing that goes backwards and it
/// goes back exactly one step. Returns when the person is done, whichever
/// way they finished.
///
/// A photo is required to post. There is no path through here that writes a
/// post without one — the camera is the only entrance, and skipping it ends
/// the journey rather than offering a caption box.
Future<void> runCaptureFlow(
  BuildContext context,
  WidgetRef ref, {
  required String taskId,
  required String taskName,
  required String sessionLabel,
  required int sessionSeconds,
  required int cumulativeSeconds,
  required double ringProgress,
  required bool canShare,
  int? milestoneHours,
  int? totalHours,
  List<Photo> bandPhotos = const [],
}) async {
  while (true) {
    final shot = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SondrCameraScreen(
          taskName: taskName,
          sessionLabel: sessionLabel,
          ringProgress: ringProgress,
        ),
      ),
    );
    if (shot == null || !context.mounted) return;

    final outcome = await Navigator.of(context).push<ReviewOutcome>(
      MaterialPageRoute(
        builder: (_) => CaptureReviewScreen(
          shot: shot,
          taskName: taskName,
          sessionLabel: sessionLabel,
          canShare: canShare,
          bandPhotos: bandPhotos,
          onKeep: (ref) => _savePrivately(
            ref,
            shot: shot,
            taskId: taskId,
            taskName: taskName,
            sessionSeconds: sessionSeconds,
            cumulativeSeconds: cumulativeSeconds,
            milestoneHours: milestoneHours,
          ).then((id) => id != null),
          onShare: (ref, caption, alsoPost) async {
            final photoId = await _savePrivately(
              ref,
              shot: shot,
              taskId: taskId,
              taskName: taskName,
              sessionSeconds: sessionSeconds,
              cumulativeSeconds: cumulativeSeconds,
              milestoneHours: milestoneHours,
            );
            if (photoId == null) return false;
            return _post(
              ref,
              shot: shot,
              caption: caption,
              alsoPost: alsoPost,
              taskName: taskName,
              sessionSeconds: sessionSeconds,
              milestoneHours: milestoneHours,
              totalHours: totalHours,
              sourceIds: [photoId, for (final p in alsoPost) p.id],
            );
          },
        ),
      ),
    );
    if (outcome != ReviewOutcome.retake) {
      if (outcome == ReviewOutcome.shared && context.mounted) {
        // Land on Feed so the fresh post is right there.
        ref.read(selectedTabProvider.notifier).set(1);
      }
      return;
    }
    if (!context.mounted) return;
  }
}

/// Upload the binary and write the private photo doc. Returns the id, or null
/// if it could not be saved.
Future<String?> _savePrivately(
  WidgetRef ref, {
  required Uint8List shot,
  required String taskId,
  required String taskName,
  required int sessionSeconds,
  required int cumulativeSeconds,
  int? milestoneHours,
}) async {
  final repo = ref.read(photosRepositoryProvider);
  if (repo == null) return null;
  try {
    final now = DateTime.now();
    final timestamp = now.microsecondsSinceEpoch;
    final photoId = Photo.docId(taskId, timestamp);
    final up = await repo.uploadPhoto(
      await _materialise(shot, photoId),
      photoId: photoId,
    );
    await repo.savePhoto(
      Photo(
        taskId: taskId,
        taskName: taskName,
        dayKey: DayKey.of(now),
        timestamp: timestamp,
        sessionSeconds: sessionSeconds,
        photoUrl: up.url,
        storagePath: up.storagePath,
        milestoneHours: milestoneHours,
        cumulativeSeconds: cumulativeSeconds,
      ),
    );
    // Every surface that shows a photo is reading a cached one until it is
    // told otherwise — see [invalidatePhotoViews].
    invalidatePhotoViews(ref);
    return photoId;
  } catch (e) {
    debugPrint('SONDR photo save error: ${e.runtimeType} :: $e');
    return null;
  }
}

/// Write the post. A milestone crossing posts as a milestone; anything else
/// posts as a session.
Future<bool> _post(
  WidgetRef ref, {
  required Uint8List shot,
  required String? caption,
  required List<Photo> alsoPost,
  required String taskName,
  required int sessionSeconds,
  required List<String> sourceIds,
  int? milestoneHours,
  int? totalHours,
}) async {
  final repo = ref.read(postsRepositoryProvider);
  if (repo == null) return false;
  try {
    final photos = <PostPhoto>[];
    final lead = await repo.uploadPostPhoto(
      await _materialise(shot, 'post'),
    );
    photos.add(PostPhoto(url: lead.url, storagePath: lead.storagePath));
    for (final p in alsoPost) {
      final up = await repo.copyToPostsSpace(p.storagePath);
      photos.add(PostPhoto(url: up.url, storagePath: up.storagePath));
    }
    if (milestoneHours != null) {
      await repo.createMilestonePost(
        taskName: taskName,
        milestoneHours: milestoneHours,
        totalHours: totalHours ?? 0,
        caption: caption,
        photos: photos,
      );
    } else {
      await repo.createSessionPost(
        taskName: taskName,
        sessionSeconds: sessionSeconds,
        caption: caption,
        photos: photos,
      );
    }
    // The post is written. Tagging its sources is a nicety from here on and
    // must never be able to fail the share — see [tagShared].
    await tagShared(ref, sourceIds);
    return true;
  } catch (e) {
    debugPrint('SONDR create post error: ${e.runtimeType} :: $e');
    return false;
  }
}

/// The repositories upload files, and a capture is bytes in memory. One temp
/// file rather than a byte-taking overload on two repositories.
Future<File> _materialise(Uint8List bytes, String name) async {
  final dir = Directory.systemTemp.createTempSync('sondr_capture');
  final file = File('${dir.path}/$name.jpg');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

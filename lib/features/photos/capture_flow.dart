import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date.dart';
import '../feed/collage_layout.dart' show kCollageMax;
import '../feed/cover_render.dart';
import '../feed/models/post.dart';
import '../feed/story_builder.dart';
import '../tasks/models/task.dart';
import '../tasks/session_log.dart';
import '../tasks/tasks_providers.dart';
import '../feed/posts_repository.dart';
import '../shell/main_shell.dart';
import 'capture_crop.dart' show photoRequiredToPost;
import 'capture_review_screen.dart';
import 'models/photo.dart';
import 'photo_refresh.dart';
import 'auto_collage.dart';
import 'collages_repository.dart';
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
  required ShareState share,
  int? milestoneHours,
  int? totalHours,
  List<Photo> bandPhotos = const [],
}) async {
  // The ring's text styles for the cover, taken now while the page is
  // here: the share happens after the camera and the review have come and
  // gone.
  final coverStyles = CoverTextStyles.of(context);
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
    if (!context.mounted) return;
    // A session post is its photo: Skip ends the journey. A milestone
    // stands without one — the review's frame shows the milestone itself
    // and the band's earlier photos can still be chosen — so Skip goes on.
    final isMilestone = milestoneHours != null;
    if (shot == null && photoRequiredToPost(isMilestone: isMilestone)) return;

    final outcome = await Navigator.of(context).push<ReviewOutcome>(
      MaterialPageRoute(
        builder: (_) => CaptureReviewScreen(
          shot: shot,
          taskName: taskName,
          sessionLabel: sessionLabel,
          share: share,
          bandPhotos: bandPhotos,
          milestoneHours: milestoneHours,
          onKeep: (ref) async {
            if (shot == null) return true;
            final saved = await _savePrivately(
              ref,
              shot: shot,
              taskId: taskId,
              taskName: taskName,
              sessionSeconds: sessionSeconds,
              cumulativeSeconds: cumulativeSeconds,
              milestoneHours: milestoneHours,
            );
            return saved != null;
          },
          onShare: (ref, caption, alsoPost) async {
            Photo? lead;
            if (shot != null) {
              lead = await _savePrivately(
                ref,
                shot: shot,
                taskId: taskId,
                taskName: taskName,
                sessionSeconds: sessionSeconds,
                cumulativeSeconds: cumulativeSeconds,
                milestoneHours: milestoneHours,
              );
              if (lead == null) return false;
            }
            return _post(
              ref,
              shot: shot,
              lead: lead,
              caption: caption,
              alsoPost: alsoPost,
              taskId: taskId,
              taskName: taskName,
              sessionSeconds: sessionSeconds,
              cumulativeSeconds: cumulativeSeconds,
              milestoneHours: milestoneHours,
              totalHours: totalHours,
              coverStyles: coverStyles,
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

/// Upload the binary and write the private photo doc. Returns the photo,
/// or null if it could not be saved.
Future<Photo?> _savePrivately(
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
    final photo = Photo(
      taskId: taskId,
      taskName: taskName,
      dayKey: DayKey.of(now),
      timestamp: timestamp,
      sessionSeconds: sessionSeconds,
      photoUrl: up.url,
      storagePath: up.storagePath,
      milestoneHours: milestoneHours,
      cumulativeSeconds: cumulativeSeconds,
    );
    await repo.savePhoto(photo);
    // Every surface that shows a photo is reading a cached one until it is
    // told otherwise — see [invalidatePhotoViews].
    // A photo taken at a crossing belongs in that milestone's collage, which
    // was composed before this photo existed.
    if (milestoneHours != null) {
      await attachCrossingPhoto(ref, taskId, milestoneHours, photoId);
    }
    invalidatePhotoViews(ref);
    return photo;
  } catch (e) {
    debugPrint('SONDR photo save error: ${e.runtimeType} :: $e');
    return null;
  }
}

/// Write the post. A milestone crossing posts as a milestone — with the
/// band's story, built here from the task, the session log and the chosen
/// photos, and its cover drawn from those photos and uploaded beside them
/// — anything else as a session, with its seconds into the band.
///
/// The photos are written in time order, the new one last: the collage's
/// order, oldest first, the crossing photo closing it.
///
/// The cover is a nicety: a render or an upload that fails never fails
/// the share — the post goes without one and the card draws the collage.
Future<bool> _post(
  WidgetRef ref, {
  required Uint8List? shot,
  required Photo? lead,
  required String? caption,
  required List<Photo> alsoPost,
  required String taskId,
  required String taskName,
  required int sessionSeconds,
  required int cumulativeSeconds,
  int? milestoneHours,
  int? totalHours,
  CoverTextStyles? coverStyles,
}) async {
  final repo = ref.read(postsRepositoryProvider);
  if (repo == null) return false;
  try {
    final ordered = [...alsoPost, ?lead]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final sourceIds = [for (final p in ordered) p.id];

    MilestoneStory? story;
    if (milestoneHours != null) {
      final task = (ref.read(tasksProvider).value ?? const <Task>[])
          .where((t) => t.id == taskId)
          .firstOrNull;
      if (task != null) {
        final log = await ref.read(sessionLogProvider).forTask(taskId);
        story = buildMilestoneStory(
          task: task,
          log: log,
          milestoneHours: milestoneHours,
          photos: ordered,
        );
      }
    }

    final photos = <PostPhoto>[];
    // The first nine, decoded for the cover, as they go up.
    final images = <ui.Image>[];
    for (var i = 0; i < ordered.length; i++) {
      final p = ordered[i];
      final isLead = lead != null && p.id == lead.id && shot != null;
      final bytes = isLead ? shot : await repo.photoBytes(p.storagePath);
      final up = await repo.uploadPostPhoto(await _materialise(bytes, 'post$i'));
      photos.add(
        PostPhoto(
          url: up.url,
          storagePath: up.storagePath,
          sessionIndex: story?.photoIndices[i],
        ),
      );
      if (milestoneHours != null && images.length < kCollageMax) {
        try {
          images.add(await decodeForCover(bytes));
        } catch (e) {
          debugPrint('SONDR cover decode error: ${e.runtimeType} :: $e');
        }
      }
    }
    if (milestoneHours != null) {
      ({String url, String storagePath})? cover;
      if (images.isNotEmpty && coverStyles != null) {
        try {
          final jpeg = await renderMilestoneCover(
            photos: images,
            milestoneHours: milestoneHours,
            styles: coverStyles,
          );
          cover = await repo.uploadPostPhoto(await _materialise(jpeg, 'cover'));
        } catch (e) {
          debugPrint('SONDR cover render error: ${e.runtimeType} :: $e');
        }
      }
      for (final image in images) {
        image.dispose();
      }
      await repo.createMilestonePost(
        taskName: taskName,
        milestoneHours: milestoneHours,
        totalHours: totalHours ?? 0,
        caption: caption,
        photos: photos,
        segments: story?.segments ?? const [],
        unit: story?.unit,
        cover: cover,
      );
      // The owner's own surfaces show the same cover their friends see.
      if (cover != null) {
        try {
          await ref
              .read(collagesRepositoryProvider)
              ?.setCover(taskId, milestoneHours, cover.url);
        } catch (e) {
          debugPrint('SONDR collage cover error: ${e.runtimeType} :: $e');
        }
      }
    } else {
      await repo.createSessionPost(
        taskName: taskName,
        sessionSeconds: sessionSeconds,
        caption: caption,
        photos: photos,
        bandSeconds: bandSecondsAfter(cumulativeSeconds),
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

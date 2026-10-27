import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date.dart';
import '../../shared/cached_photo.dart';
import '../auth/profile_repository.dart';
import '../feed/collage_layout.dart' show PhotoFraming, kCollageMax;
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
import 'milestone_arrange_screen.dart';
import 'milestone_arrangement.dart';
import 'milestone_final_look_screen.dart';
import 'models/photo.dart';
import 'photo_refresh.dart';
import 'auto_collage.dart';
import 'collages_repository.dart';
import 'photos_repository.dart';
import 'sondr_camera.dart';

/// The whole posting journey. A session: camera → review → keep or share.
/// A milestone: camera → Arrange → Final look → keep or share, where Skip
/// at the camera goes on to Arrange without a new photo.
///
/// One loop, because "retake" is the only thing that goes backwards and it
/// goes back exactly one step — keeping, for a milestone, everything that
/// was arranged. Returns when the person is done, whichever way they
/// finished.
///
/// A session photo is required to post: skipping the camera ends that
/// journey rather than offering a caption box.
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
  // A milestone's arrangement outlives a retake.
  Arrangement? arrangement;
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

    if (milestoneHours != null) {
      final result = await _milestoneJourney(
        context,
        ref,
        shot: shot,
        arrangement: arrangement,
        taskId: taskId,
        taskName: taskName,
        sessionSeconds: sessionSeconds,
        cumulativeSeconds: cumulativeSeconds,
        milestoneHours: milestoneHours,
        totalHours: totalHours,
        bandPhotos: bandPhotos,
        coverStyles: coverStyles,
      );
      if (!context.mounted) return;
      if (result.done) {
        // Land on Feed so the fresh post is right there.
        if (result.shared) ref.read(selectedTabProvider.notifier).set(1);
        return;
      }
      arrangement = result.arrangement;
      continue;
    }

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

/// Arrange, then the final look, for a milestone. Returns whether the
/// journey is over (kept or shared) or goes back to the camera (a retake,
/// with the arrangement to carry on from).
Future<({bool done, bool shared, Arrangement? arrangement})> _milestoneJourney(
  BuildContext context,
  WidgetRef ref, {
  required Uint8List? shot,
  required Arrangement? arrangement,
  required String taskId,
  required String taskName,
  required int sessionSeconds,
  required int cumulativeSeconds,
  required int milestoneHours,
  required int? totalHours,
  required List<Photo> bandPhotos,
  required CoverTextStyles coverStyles,
}) async {
  final entries = [
    for (final p in bandPhotos)
      ArrangeEntry(id: p.id, image: cachedPhotoProvider(p.photoUrl), photo: p),
    if (shot != null)
      ArrangeEntry(id: ArrangeEntry.newShotId, image: MemoryImage(shot), shot: shot),
  ];
  File? shotFile;
  var current = arrangement;

  Future<bool> keep(WidgetRef ref) async {
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
  }

  while (true) {
    final arranged = await Navigator.of(context).push<ArrangeOutcome>(
      MaterialPageRoute(
        builder: (_) => MilestoneArrangeScreen(
          entries: entries,
          milestoneHours: milestoneHours,
          initial: current,
          onKeep: keep,
        ),
      ),
    );
    if (!context.mounted || arranged == null) {
      return (done: true, shared: false, arrangement: current);
    }
    switch (arranged.kind) {
      case ArrangeOutcomeKind.retake:
        return (done: false, shared: false, arrangement: arranged.arrangement);
      case ArrangeOutcomeKind.kept:
        return (done: true, shared: false, arrangement: arranged.arrangement);
      case ArrangeOutcomeKind.next:
        current = arranged.arrangement;
    }
    final arrangementNow = current ?? Arrangement.initial(entries);
    final chosen = arrangementNow.chosen(entries);

    // The card as it will be: the new shot stands in as a file until it
    // is uploaded, and the story is told for the photos as arranged.
    if (shot != null) shotFile ??= await _materialise(shot, 'preview');
    final now = DateTime.now();
    final asPhotos = [
      for (final e in chosen)
        e.photo ??
            Photo(
              taskId: taskId,
              taskName: taskName,
              dayKey: DayKey.of(now),
              timestamp: now.microsecondsSinceEpoch,
              sessionSeconds: sessionSeconds,
              photoUrl: '',
              storagePath: '',
              milestoneHours: milestoneHours,
              cumulativeSeconds: cumulativeSeconds,
            ),
    ];
    final story = await _storyFor(ref, taskId: taskId, milestoneHours: milestoneHours, photos: asPhotos);
    final previewPhotos = [
      for (var i = 0; i < chosen.length; i++)
        PostPhoto(
          url: chosen[i].isNew ? shotFile!.uri.toString() : chosen[i].photo!.photoUrl,
          storagePath: '',
          sessionIndex: story?.photoIndices[i],
          framing: arrangementNow.framingOf(chosen[i].id),
        ),
    ];
    final profile = await ref.read(currentProfileProvider.future);
    if (!context.mounted) return (done: true, shared: false, arrangement: current);

    final look = await Navigator.of(context).push<FinalLookOutcome>(
      MaterialPageRoute(
        builder: (_) => MilestoneFinalLookScreen(
          photos: previewPhotos,
          milestoneHours: milestoneHours,
          taskName: taskName,
          handle: profile?.username ?? '',
          segments: story?.segments ?? const [],
          unit: story?.unit,
          onKeep: keep,
          onShare: (ref, caption) async {
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
              alsoPost: const [],
              arranged: [
                for (final e in chosen)
                  (photo: e.photo ?? lead!, framing: arrangementNow.framingOf(e.id)),
              ],
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
    if (!context.mounted || look == null) {
      return (done: true, shared: false, arrangement: current);
    }
    switch (look.kind) {
      case FinalLookOutcomeKind.back:
        continue;
      case FinalLookOutcomeKind.kept:
        return (done: true, shared: false, arrangement: current);
      case FinalLookOutcomeKind.shared:
        return (done: true, shared: true, arrangement: current);
    }
  }
}

/// The band's story for [photos], or null when the task cannot be found.
Future<MilestoneStory?> _storyFor(
  WidgetRef ref, {
  required String taskId,
  required int milestoneHours,
  required List<Photo> photos,
}) async {
  final task = (ref.read(tasksProvider).value ?? const <Task>[])
      .where((t) => t.id == taskId)
      .firstOrNull;
  if (task == null) return null;
  final log = await ref.read(sessionLogProvider).forTask(taskId);
  return buildMilestoneStory(
    task: task,
    log: log,
    milestoneHours: milestoneHours,
    photos: photos,
  );
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
  List<({Photo photo, PhotoFraming framing})>? arranged,
}) async {
  final repo = ref.read(postsRepositoryProvider);
  if (repo == null) return false;
  try {
    // A milestone's photos come as arranged — the collage's order, each
    // with its framing; a session's in time order.
    final ordered = arranged != null
        ? [for (final a in arranged) a.photo]
        : ([...alsoPost, ?lead]..sort((a, b) => a.timestamp.compareTo(b.timestamp)));
    final framings = [
      for (final a in arranged ?? const <({Photo photo, PhotoFraming framing})>[])
        a.framing,
    ];
    final sourceIds = [for (final p in ordered) p.id];

    MilestoneStory? story;
    if (milestoneHours != null) {
      story = await _storyFor(ref, taskId: taskId, milestoneHours: milestoneHours, photos: ordered);
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
          framing: i < framings.length ? framings[i] : PhotoFraming.none,
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
      ({String url, String storagePath})? thumb;
      if (images.isNotEmpty && coverStyles != null) {
        try {
          final jpeg = await renderMilestoneCover(
            photos: images,
            milestoneHours: milestoneHours,
            styles: coverStyles,
            framings: framings,
          );
          cover = await repo.uploadPostPhoto(await _materialise(jpeg, 'cover'));
        } catch (e) {
          debugPrint('SONDR cover render error: ${e.runtimeType} :: $e');
        }
        try {
          final jpeg = await renderMilestoneThumb(photos: images, framings: framings);
          thumb = await repo.uploadPostPhoto(await _materialise(jpeg, 'thumb'));
        } catch (e) {
          debugPrint('SONDR thumb render error: ${e.runtimeType} :: $e');
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
        thumb: thumb,
      );
      // The owner's own surfaces show the same images their friends see.
      if (cover != null || thumb != null) {
        try {
          await ref.read(collagesRepositoryProvider)?.setCover(
            taskId,
            milestoneHours,
            coverUrl: cover?.url,
            thumbUrl: thumb?.url,
          );
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

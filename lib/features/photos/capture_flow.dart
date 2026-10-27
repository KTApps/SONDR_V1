import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/utils/date.dart';
import '../../core/debug_flags.dart';
import '../../shared/cached_photo.dart';
import '../auth/profile_repository.dart';
import '../feed/collage_layout.dart' show PhotoFraming;
import '../feed/cover_render.dart';
import '../feed/firebase_share_backend.dart';
import '../feed/models/post.dart';
import '../feed/share_job.dart';
import '../feed/share_trace.dart';
import '../feed/story_builder.dart';
import '../tasks/models/task.dart';
import '../tasks/session_log.dart';
import '../tasks/tasks_providers.dart';
import '../shell/main_shell.dart';
import 'capture_crop.dart' show photoRequiredToPost;
import 'capture_review_screen.dart';
import 'milestone_arrange_screen.dart';
import 'milestone_arrangement.dart';
import 'milestone_final_look_screen.dart';
import 'models/photo.dart';
import 'photo_refresh.dart';
import 'auto_collage.dart';
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
  // The share's timings, when the debug tools are on.
  ShareTrace? trace;
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
        share: share,
      );
      if (!context.mounted) return;
      if (result.done) {
        // Land on Feed so the fresh post is right there.
        if (result.shared) {
          ref.read(selectedTabProvider.notifier).set(1);
          result.trace?.feedShown();
        }
        return;
      }
      arrangement = result.arrangement;
      continue;
    }

    // The review shows the card as it will be posted: the shot stands in
    // as a file, and the card is the author's.
    final shotFile = shot == null ? null : await _materialise(shot, 'preview');
    final profile = await ref.read(currentProfileProvider.future);
    if (!context.mounted) return;
    final outcome = await Navigator.of(context).push<ReviewOutcome>(
      MaterialPageRoute(
        builder: (_) => CaptureReviewScreen(
          shotUrl: shotFile?.uri.toString(),
          taskName: taskName,
          sessionSeconds: sessionSeconds,
          bandSeconds: bandSecondsAfter(cumulativeSeconds),
          handle: profile?.username ?? '',
          share: share,
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
          onShare: (ref, caption) async {
            // A session post is its photo. The post goes out now, the
            // upload behind it — the same job a milestone runs.
            trace = await _beginShare(
              ref,
              type: PostType.session,
              shot: shot,
              chosen: [
                if (shot != null) (photo: null, framing: PhotoFraming.none),
              ],
              handle: profile?.username ?? '',
              displayName: profile?.displayName ?? '',
              caption: caption,
              taskId: taskId,
              taskName: taskName,
              sessionSeconds: sessionSeconds,
              cumulativeSeconds: cumulativeSeconds,
              coverStyles: coverStyles,
            );
            return trace != null;
          },
        ),
      ),
    );
    if (outcome != ReviewOutcome.retake) {
      if (outcome == ReviewOutcome.shared && context.mounted) {
        // Land on Feed so the fresh post is right there.
        ref.read(selectedTabProvider.notifier).set(1);
        trace?.feedShown();
      }
      return;
    }
    if (!context.mounted) return;
  }
}

/// Arrange, then the final look, for a milestone. Returns whether the
/// journey is over (kept or shared) or goes back to the camera (a retake,
/// with the arrangement to carry on from).
Future<({bool done, bool shared, Arrangement? arrangement, ShareTrace? trace})> _milestoneJourney(
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
  required ShareState share,
}) async {
  final entries = [
    for (final p in bandPhotos)
      ArrangeEntry(id: p.id, image: cachedPhotoProvider(p.photoUrl), photo: p),
    if (shot != null)
      ArrangeEntry(id: ArrangeEntry.newShotId, image: MemoryImage(shot), shot: shot),
  ];
  File? shotFile;
  var current = arrangement;
  ShareTrace? trace;

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
      return (done: true, shared: false, arrangement: current, trace: null);
    }
    switch (arranged.kind) {
      case ArrangeOutcomeKind.retake:
        return (done: false, shared: false, arrangement: arranged.arrangement, trace: null);
      case ArrangeOutcomeKind.kept:
        return (done: true, shared: false, arrangement: arranged.arrangement, trace: null);
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
    if (!context.mounted) return (done: true, shared: false, arrangement: current, trace: null);

    final look = await Navigator.of(context).push<FinalLookOutcome>(
      MaterialPageRoute(
        builder: (_) => MilestoneFinalLookScreen(
          photos: previewPhotos,
          milestoneHours: milestoneHours,
          taskName: taskName,
          handle: profile?.username ?? '',
          share: share,
          segments: story?.segments ?? const [],
          unit: story?.unit,
          onKeep: keep,
          onShare: (ref, caption) async {
            // The post goes out now, as arranged; everything slow runs
            // behind it as a job.
            trace = await _beginShare(
              ref,
              type: PostType.milestone,
              shot: shot,
              chosen: [
                for (final e in chosen)
                  (photo: e.photo, framing: arrangementNow.framingOf(e.id)),
              ],
              caption: caption,
              taskId: taskId,
              taskName: taskName,
              sessionSeconds: sessionSeconds,
              cumulativeSeconds: cumulativeSeconds,
              milestoneHours: milestoneHours,
              totalHours: totalHours,
              story: story,
              handle: profile?.username ?? '',
              displayName: profile?.displayName ?? '',
              coverStyles: coverStyles,
            );
            return trace != null;
          },
        ),
      ),
    );
    if (!context.mounted || look == null) {
      return (done: true, shared: false, arrangement: current, trace: null);
    }
    switch (look.kind) {
      case FinalLookOutcomeKind.back:
        continue;
      case FinalLookOutcomeKind.kept:
        return (done: true, shared: false, arrangement: current, trace: null);
      case FinalLookOutcomeKind.shared:
        return (done: true, shared: true, arrangement: current, trace: trace);
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

/// Share: the post is written at once and the job started. Returns the
/// trace (a plain one when the debug tools are off), or null when there is
/// nobody to share as.
///
/// [chosen] is the post's photos in order — a band photo, or null for the
/// new [shot] — each with its framing. [story] is the band's, already
/// told for the final look, so it is not told again.
Future<ShareTrace?> _beginShare(
  WidgetRef ref, {
  required PostType type,
  required Uint8List? shot,
  required List<({Photo? photo, PhotoFraming framing})> chosen,
  required String? caption,
  required String taskId,
  required String taskName,
  required int sessionSeconds,
  required int cumulativeSeconds,
  required CoverTextStyles coverStyles,
  int? milestoneHours,
  int? totalHours,
  MilestoneStory? story,
  String? handle,
  String? displayName,
}) async {
  final runner = ref.read(shareJobRunnerProvider);
  if (runner == null) return null;
  try {
    final now = DateTime.now();
    final postId = runner.backend.newPostId();
    final trace = ShareTrace(postId);
    // The new shot, kept where a job can find it after a relaunch.
    final shotPath = shot == null ? null : await _keepForShare(shot, postId);
    final shotTs = now.microsecondsSinceEpoch;
    final shotPhotoId = Photo.docId(taskId, shotTs);
    final photos = <ShareJobPhoto>[
      for (var i = 0; i < chosen.length; i++)
        ShareJobPhoto(
          id: chosen[i].photo?.id ?? shotPhotoId,
          localPath: chosen[i].photo == null ? shotPath : null,
          sourceStoragePath: chosen[i].photo?.storagePath,
          sourceUrl: chosen[i].photo?.photoUrl,
          framing: chosen[i].framing,
          sessionIndex: story?.photoIndices[i],
          isNew: chosen[i].photo == null,
        ),
    ];
    final job = ShareJob(
      postId: postId,
      type: type,
      taskId: taskId,
      taskName: taskName,
      sessionSeconds: sessionSeconds,
      cumulativeSeconds: cumulativeSeconds,
      photos: photos,
      createdAtMs: now.millisecondsSinceEpoch,
      milestoneHours: milestoneHours,
      totalHours: totalHours,
      caption: caption,
      segments: story?.segments ?? const [],
      unit: story?.unit,
      shotTimestamp: shot == null ? null : shotTs,
      bandSeconds: type == PostType.session ? bandSecondsAfter(cumulativeSeconds) : null,
    );
    var author = PostAuthor(username: handle ?? '', displayName: displayName ?? '');
    if (handle == null) {
      final profile = await ref.read(currentProfileProvider.future);
      author = PostAuthor(username: profile?.username ?? '', displayName: profile?.displayName ?? '');
    }
    runner.coverStyles = coverStyles;
    trace.mark('job built');
    await runner.begin(job, author, trace: kDebugTools ? trace : null);
    return trace;
  } catch (e) {
    debugPrint('SONDR share begin error: ${e.runtimeType} :: $e');
    return null;
  }
}

/// The shot, written under the app's own support directory — the temp
/// directory can be emptied while the app is not running, and a job has
/// to find its bytes after a relaunch.
Future<String> _keepForShare(Uint8List bytes, String postId) async {
  final base = await getApplicationSupportDirectory();
  final dir = Directory('${base.path}/sondr_share/$postId')..createSync(recursive: true);
  final file = File('${dir.path}/shot.jpg');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// The repositories upload files, and a capture is bytes in memory. One temp
/// file rather than a byte-taking overload on two repositories.
Future<File> _materialise(Uint8List bytes, String name) async {
  final dir = Directory.systemTemp.createTempSync('sondr_capture');
  final file = File('${dir.path}/$name.jpg');
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

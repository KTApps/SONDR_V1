import 'package:flutter/foundation.dart';

import '../photos/collage_selection.dart' show kMilestoneBandSeconds;
import '../photos/models/photo.dart';
import '../tasks/models/task.dart';
import '../tasks/session_log.dart';
import 'band_story.dart';
import 'models/post.dart';

/// What a milestone post stores about its band, built at share time.
@immutable
class MilestoneStory {
  const MilestoneStory({required this.segments, required this.unit, required this.photoIndices});

  final List<PostSegment> segments;
  final SegmentUnit unit;

  /// For each photo given to [buildMilestoneStory], in the same order, the
  /// segment it belongs to (null if none).
  final List<int?> photoIndices;
}

/// The story of the band [milestoneHours] closed.
///
/// Sessions when the log covers the band; otherwise days from the task's
/// own record, clipped to the band. One unit per post, never both. Each
/// photo is mapped to its segment by its timestamp (by session) or its
/// day (by day); a photo that lands on no segment keeps no index.
MilestoneStory buildMilestoneStory({
  required Task task,
  required List<SessionRecord> log,
  required int milestoneHours,
  required List<Photo> photos,
}) {
  final band = bandOf(milestoneHours, stepHours: Task.milestoneStepHours);
  final fromLog = sessionSegments(
    log: log,
    bandStart: band.start,
    bandEnd: band.end,
    totalSeconds: task.totalSeconds,
  );
  final segments = fromLog ??
      daySegments(
        secondsByDay: task.secondsByDay,
        bandStart: band.start,
        bandEnd: band.end,
      );
  final indices = [
    for (final p in photos)
      segmentIndexForPhoto(
        photoTimestamp: p.timestamp,
        photoDayKey: p.dayKey,
        segments: segments,
      ),
  ];
  final marked = markPhotos(segments.segments, indices);
  return MilestoneStory(
    segments: [
      for (final s in marked)
        PostSegment(at: s.at, seconds: s.seconds, photo: s.photo),
    ],
    unit: segments.unit,
    photoIndices: indices,
  );
}

/// A session post's seconds into its band once the session was credited.
int bandSecondsAfter(int cumulativeSeconds) =>
    cumulativeSeconds % kMilestoneBandSeconds;

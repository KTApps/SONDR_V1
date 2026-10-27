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

  /// Null when the log does not reach back to the band: no story.
  final SegmentUnit? unit;

  /// For each photo given to [buildMilestoneStory], in the same order, the
  /// segment it belongs to (null if none).
  final List<int?> photoIndices;
}

/// The story of the band [milestoneHours] closed.
///
/// Sessions, when the log covers the band; a band the log does not reach
/// back to has no story at all, and its photos no session. Each photo is
/// mapped to its session by its timestamp; a photo that lands on none
/// keeps no index.
MilestoneStory buildMilestoneStory({
  required Task task,
  required List<SessionRecord> log,
  required int milestoneHours,
  required List<Photo> photos,
}) {
  final band = bandOf(milestoneHours, stepHours: Task.milestoneStepHours);
  final segments = sessionSegments(
    log: log,
    bandStart: band.start,
    bandEnd: band.end,
    totalSeconds: task.totalSeconds,
  );
  if (segments == null) {
    return MilestoneStory(
      segments: const [],
      unit: null,
      photoIndices: List<int?>.filled(photos.length, null),
    );
  }
  final indices = [
    for (final p in photos)
      segmentIndexForPhoto(photoTimestamp: p.timestamp, segments: segments),
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

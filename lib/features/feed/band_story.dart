import 'package:flutter/foundation.dart';

import '../tasks/session_log.dart';

/// What a milestone story is made of: the effort of one 20-hour band, cut
/// into segments, and which segment each photo belongs to.
///
/// Pure arithmetic, no I/O, so every rule here is unit-tested in isolation:
/// whether the session log covers the band, how a session is clipped at the
/// band's edges, and the photo → segment mapping. A band the log does not
/// reach back to has no segments: there is no telling it by days.

/// One segment of the band's effort.
@immutable
class BandSegment {
  const BandSegment({
    required this.at,
    required this.seconds,
    this.photo = false,
  });

  /// When the session began, epoch milliseconds.
  final int at;
  final int seconds;

  /// Whether one of the post's photos belongs to this segment.
  final bool photo;

  BandSegment withPhoto() => BandSegment(at: at, seconds: seconds, photo: true);

  @override
  bool operator ==(Object other) =>
      other is BandSegment &&
      other.at == at &&
      other.seconds == seconds &&
      other.photo == photo;

  @override
  int get hashCode => Object.hash(at, seconds, photo);

  @override
  String toString() => 'BandSegment(at: $at, seconds: $seconds, photo: $photo)';
}

/// What a segment stands for. Sessions only: a post from the days when a
/// band could be told by its days is parsed as having no story.
enum SegmentUnit { session }

@immutable
class BandSegments {
  const BandSegments({required this.segments, required this.unit});

  final List<BandSegment> segments;
  final SegmentUnit unit;

  int get totalSeconds => segments.fold(0, (s, e) => s + e.seconds);
}

/// How far the log's sum may fall short of the band's start and still be
/// taken as covering it: a credit is whole seconds, and a session that
/// straddled the log's own beginning is at most a minute off.
const int kBandCoverageToleranceSeconds = 60;

/// The band's segments from the session log — or null when the log does
/// not reach back to the band's start, in which case the post has no story.
///
/// Time the log never saw is taken to have come FIRST (the log is
/// forward-only, so everything it is missing predates it): the walk
/// starts at `totalSeconds − sum(log)` and lays each session down in
/// order. A session is clipped where it crosses either edge of the band,
/// so the segments sum to the band exactly.
BandSegments? sessionSegments({
  required List<SessionRecord> log,
  required int bandStart,
  required int bandEnd,
  required int totalSeconds,
  int tolerance = kBandCoverageToleranceSeconds,
}) {
  final sorted = [...log]..sort((a, b) => a.at.compareTo(b.at));
  final logged = sorted.fold(0, (s, r) => s + r.seconds);
  final unlogged = totalSeconds - logged;
  if (unlogged > bandStart + tolerance) return null;

  var cursor = unlogged < 0 ? 0 : unlogged;
  final out = <BandSegment>[];
  for (final r in sorted) {
    final start = cursor;
    final end = cursor + r.seconds;
    cursor = end;
    final from = start < bandStart ? bandStart : start;
    final to = end > bandEnd ? bandEnd : end;
    if (to > from) out.add(BandSegment(at: r.at, seconds: to - from));
  }
  if (out.isEmpty) return null;
  return BandSegments(segments: out, unit: SegmentUnit.session);
}

/// Which segment a photo belongs to, or null if none does.
///
/// A photo is taken as a session ends, so it is the last segment that
/// began before it. [photoTimestamp] is MICROSECONDS, as `Photo.timestamp`
/// is stored.
int? segmentIndexForPhoto({
  required int photoTimestamp,
  required BandSegments segments,
}) {
  final ms = photoTimestamp ~/ 1000;
  int? found;
  for (var i = 0; i < segments.segments.length; i++) {
    if (segments.segments[i].at <= ms) found = i;
  }
  return found;
}

/// The segments with the ones that have a photo marked.
List<BandSegment> markPhotos(List<BandSegment> segments, Iterable<int?> indices) {
  final marked = [...segments];
  for (final i in indices) {
    if (i != null && i >= 0 && i < marked.length) marked[i] = marked[i].withPhoto();
  }
  return marked;
}

/// The band a milestone of [milestoneHours] closed: `[start, end)` in
/// seconds of the task's lifetime.
({int start, int end}) bandOf(int milestoneHours, {int stepHours = 20}) {
  final end = milestoneHours * 3600;
  return (start: end - stepHours * 3600, end: end);
}

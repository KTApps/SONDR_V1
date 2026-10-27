import 'package:flutter/foundation.dart';

import '../../core/utils/date.dart';
import '../../core/utils/duration_format.dart';
import 'models/post.dart';

/// What a milestone card steps through, and what the ring says on each
/// page. Pure, so the page list and the centre text are tested without a
/// widget.

enum MilestonePageKind { cover, photo, noPhoto }

@immutable
class MilestonePage {
  const MilestonePage(this.kind, {this.photoIndex});

  final MilestonePageKind kind;

  /// Which of the post's photos a photo page shows. Null otherwise.
  final int? photoIndex;

  @override
  bool operator ==(Object other) =>
      other is MilestonePage &&
      other.kind == kind &&
      other.photoIndex == photoIndex;

  @override
  int get hashCode => Object.hash(kind, photoIndex);

  @override
  String toString() => 'MilestonePage($kind, $photoIndex)';
}

/// The pages: the cover, then every photo in stored order — the collage's
/// own order, top-left tile first. One photo is the cover alone; none is
/// the frame with the milestone itself.
List<MilestonePage> milestonePages(MilestonePost post) {
  final n = post.photos.length;
  if (n == 0) return const [MilestonePage(MilestonePageKind.noPhoto)];
  if (n == 1) return const [MilestonePage(MilestonePageKind.cover)];
  return [
    const MilestonePage(MilestonePageKind.cover),
    for (var i = 0; i < n; i++)
      MilestonePage(MilestonePageKind.photo, photoIndex: i),
  ];
}

/// The session a photo page's photo belongs to, or null when the post
/// has no story or the photo no session.
int? sessionOf(MilestonePage page, MilestonePost post) {
  if (page.kind != MilestonePageKind.photo || !post.hasStory) return null;
  final i = page.photoIndex;
  if (i == null || i >= post.photos.length) return null;
  final s = post.photos[i].sessionIndex;
  if (s == null || s < 0 || s >= post.segments.length) return null;
  return s;
}

/// What the ring says on a page: the milestone's hours, or on a photo's
/// page that photo's session — how long it was, over its date. A photo
/// whose session is unknown says the hours, as the cover does.
({String figure, String unit}) ringCentre(MilestonePage page, MilestonePost post) {
  final s = sessionOf(page, post);
  if (s == null) return (figure: '${post.milestoneHours}', unit: 'hours');
  final segment = post.segments[s];
  return (
    figure: DurationFormat.hm(Duration(seconds: segment.seconds)),
    unit: segmentDate(segment),
  );
}

/// "6 Oct": the day a session began.
String segmentDate(PostSegment segment) {
  final d = DateTime.fromMillisecondsSinceEpoch(segment.at);
  return '${d.day} ${DayKey.monthName(d.month).substring(0, 3)}';
}

import 'package:flutter/foundation.dart';

import '../../core/utils/duration_format.dart';
import 'models/post.dart';

/// What a milestone card steps through, and what each page says of its
/// session. Pure, so the page list and the lines are tested without a
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

/// What a photo page's ring shows: the band's seconds before the photo's
/// session — the sessions ahead of it in the story — and the session's
/// own. Null when the session is unknown: no ring then.
({int before, int seconds})? pageSession(MilestonePage page, MilestonePost post) {
  final s = sessionOf(page, post);
  if (s == null) return null;
  var before = 0;
  for (var i = 0; i < s; i++) {
    before += post.segments[i].seconds;
  }
  return (before: before, seconds: post.segments[s].seconds);
}

/// The task line on a page: the task alone on the cover — and on a photo
/// whose session is unknown — or "Spanish · 2h 40m" on a photo's page.
String pageTaskLine(MilestonePage page, MilestonePost post) {
  final session = pageSession(page, post);
  if (session == null) return post.taskName;
  return '${post.taskName} · ${DurationFormat.hm(Duration(seconds: session.seconds))}';
}

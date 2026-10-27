import 'package:flutter/foundation.dart';

import '../band_story.dart' show SegmentUnit;

/// Feed posts. Two kinds give the feed its rhythm (big milestone cards and
/// tiny session logs); a sealed hierarchy parsed by `type` lets the feed
/// switch on the kind cleanly. A third, a habit streak, was carried here
/// unbuilt for long enough to be worth removing — nothing ever created one,
/// and a `type` the app does not write parses as a session log. All share an author, timestamp,
/// optional caption and a list of attached [photos], and an `audience` (the
/// author's accepted friends at post time + self) that scopes who can read it —
/// see the friends-only feed rules.
enum PostType { milestone, session }

/// Denormalized author identity stored on each post so the feed renders without
/// extra profile reads (which the rules keep private).
class PostAuthor {
  const PostAuthor({required this.username, required this.displayName});

  final String username;
  final String displayName;

  String get label => displayName.isNotEmpty ? displayName : '@$username';

  Map<String, dynamic> toMap() => {
    'username': username,
    'displayName': displayName,
  };

  factory PostAuthor.fromMap(Map<String, dynamic> map) => PostAuthor(
    username: (map['username'] as String?) ?? '',
    displayName: (map['displayName'] as String?) ?? '',
  );
}

/// One photo attached to a post: the friends-readable download [url] plus the
/// Storage [storagePath] it lives at (under the author's posts space). The path
/// is kept so the binary can be deleted when the post is — it points at the
/// post's own copy, never the private gallery original. Posts are multi-photo
/// (the [Post.photos] list); today's flows attach at most one, but this schema
/// is the keystone the multi-photo feed rebuild turns on.
class PostPhoto {
  const PostPhoto({
    required this.url,
    required this.storagePath,
    this.sessionIndex,
  });

  final String url;
  final String storagePath;

  /// Which of the post's [MilestonePost.segments] this photo belongs to —
  /// the session it was taken at the end of. Null on a session post, and
  /// on milestone posts written before stories.
  final int? sessionIndex;

  Map<String, dynamic> toMap() => {
    'url': url,
    'storagePath': storagePath,
    if (sessionIndex != null) 'sessionIndex': sessionIndex,
  };

  factory PostPhoto.fromMap(Map<String, dynamic> map) => PostPhoto(
    url: (map['url'] as String?) ?? '',
    storagePath: (map['storagePath'] as String?) ?? '',
    sessionIndex: map['sessionIndex'] is num
        ? (map['sessionIndex'] as num).toInt()
        : null,
  );

  /// Value equality so a photo list round-trips (write → read → equal).
  @override
  bool operator ==(Object other) =>
      other is PostPhoto &&
      other.url == url &&
      other.storagePath == storagePath &&
      other.sessionIndex == sessionIndex;

  @override
  int get hashCode => Object.hash(url, storagePath, sessionIndex);
}

/// One segment of a milestone band's effort, as stored on the post.
///
/// A session — or, on a post whose task predates the session log, a day.
/// Which it is, is the post's [MilestonePost.unit]; never both in one post.
@immutable
class PostSegment {
  const PostSegment({
    required this.at,
    required this.seconds,
    this.photo = false,
  });

  /// Epoch milliseconds: the session's start, or the day's midnight.
  final int at;
  final int seconds;

  /// Whether one of the post's photos belongs to it.
  final bool photo;

  Map<String, dynamic> toMap() => {'at': at, 'seconds': seconds, 'photo': photo};

  static PostSegment? fromMap(Map<String, dynamic> map) {
    final at = map['at'];
    final seconds = map['seconds'];
    if (at is! num || seconds is! num) return null;
    return PostSegment(
      at: at.toInt(),
      seconds: seconds.toInt(),
      photo: map['photo'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PostSegment &&
      other.at == at &&
      other.seconds == seconds &&
      other.photo == photo;

  @override
  int get hashCode => Object.hash(at, seconds, photo);
}

sealed class Post {
  const Post({
    required this.id,
    required this.authorUid,
    required this.author,
    required this.createdAt,
    required this.caption,
    this.photos = const [],
    this.likeCount = 0,
    this.commentCount = 0,
  });

  final String id;
  final String authorUid;
  final PostAuthor author;

  /// Null only briefly between a local write and the server timestamp landing.
  final DateTime? createdAt;
  final String? caption;

  /// The post's attached photos, in display order; empty for a photoless post.
  /// Replaces the old single `photoUrl` — the multi-photo schema is the pivot of
  /// the feed rebuild.
  final List<PostPhoto> photos;

  /// Denormalized interaction counts, bumped ±1 via batched writes alongside the
  /// like mirror / comment doc. They ride the feed stream, so cards show live
  /// counts with no extra reads.
  final int likeCount;
  final int commentCount;

  PostType get type;

  factory Post.fromMap(String id, Map<String, dynamic> map) {
    final author = PostAuthor.fromMap(
      Map<String, dynamic>.from((map['author'] as Map?) ?? const {}),
    );
    final authorUid = (map['authorUid'] as String?) ?? '';
    final createdAt = _parseTime(map['createdAt']);
    final caption = map['caption'] as String?;
    final photos = _parsePhotos(map['photos']);
    final likeCount = _int(map['likeCount']);
    final commentCount = _int(map['commentCount']);

    switch (map['type']) {
      case 'milestone':
        return MilestonePost(
          id: id,
          authorUid: authorUid,
          author: author,
          createdAt: createdAt,
          caption: caption,
          photos: photos,
          likeCount: likeCount,
          commentCount: commentCount,
          taskName: (map['taskName'] as String?) ?? '',
          milestoneHours: _int(map['milestoneHours']),
          totalHours: _int(map['totalHours']),
          coverUrl: map['coverUrl'] as String?,
          coverStoragePath: map['coverStoragePath'] as String?,
          segments: _parseSegments(map['sessions']),
          unit: switch (map['unit']) {
            'session' => SegmentUnit.session,
            _ => null,
          },
        );
      default:
        return SessionPost(
          id: id,
          authorUid: authorUid,
          author: author,
          createdAt: createdAt,
          caption: caption,
          photos: photos,
          likeCount: likeCount,
          commentCount: commentCount,
          taskName: (map['taskName'] as String?) ?? '',
          sessionSeconds: _int(map['sessionSeconds']),
          bandSeconds: map['bandSeconds'] is num
              ? (map['bandSeconds'] as num).toInt()
              : null,
        );
    }
  }
}

/// Milestone reached — the hero is the completed dual ring + big hours figure.
class MilestonePost extends Post {
  const MilestonePost({
    required super.id,
    required super.authorUid,
    required super.author,
    required super.createdAt,
    required super.caption,
    super.photos,
    super.likeCount,
    super.commentCount,
    required this.taskName,
    required this.milestoneHours,
    required this.totalHours,
    this.segments = const [],
    this.unit,
    this.coverUrl,
    this.coverStoragePath,
  });

  final String taskName;

  /// The milestone band reached (20, 40, 60, …).
  final int milestoneHours;

  /// Lifetime hours on the task at post time.
  final int totalHours;

  /// The band's effort, segment by segment, chronological — the story's
  /// bar. Empty on posts written before stories existed; they render as
  /// a single page with no bar.
  final List<PostSegment> segments;

  /// What a segment is: a session, or a day where the task predates the
  /// session log. Null when there are no segments.
  final SegmentUnit? unit;

  /// Whether this post carries a story at all.
  bool get hasStory => segments.isNotEmpty && unit != null;

  /// The cover as one image — the collage, the scrim and the ring, drawn
  /// at share time and uploaded beside the photos. The feed shows it for
  /// the first page when it is there and draws the collage when it is not
  /// (every post from before covers were made). What a share to another
  /// app would send.
  final String? coverUrl;

  /// Where the cover's binary lives, so deleting the post removes it.
  final String? coverStoragePath;

  @override
  PostType get type => PostType.milestone;
}

/// Session log — deliberately tiny ("logged 2h 15m · Spanish").
class SessionPost extends Post {
  const SessionPost({
    required super.id,
    required super.authorUid,
    required super.author,
    required super.createdAt,
    required super.caption,
    super.photos,
    super.likeCount,
    super.commentCount,
    required this.taskName,
    required this.sessionSeconds,
    this.bandSeconds,
  });

  final String taskName;
  final int sessionSeconds;

  /// The task's seconds into its current 20-hour band once this session
  /// was credited — what the card's ring fills to. Null on posts written
  /// before it was stored; they show no ring.
  final int? bandSeconds;

  @override
  PostType get type => PostType.session;
}

int _int(dynamic v) => v is num ? v.toInt() : 0;

/// Parse the stored `sessions` array, tolerating a missing or malformed
/// field (→ empty) so old docs never throw.
List<PostSegment> _parseSegments(dynamic v) {
  if (v is! List) return const [];
  return [
    for (final e in v)
      if (e is Map) ?PostSegment.fromMap(Map<String, dynamic>.from(e)),
  ];
}

/// Parse the stored `photos` array into [PostPhoto]s, tolerating a missing or
/// malformed field (→ empty) so old/partial docs never throw.
List<PostPhoto> _parsePhotos(dynamic v) {
  if (v is! List) return const [];
  return [
    for (final e in v)
      if (e is Map) PostPhoto.fromMap(Map<String, dynamic>.from(e)),
  ];
}

/// Tolerates a Firestore `Timestamp` (duck-typed via `toDate()` so this model
/// stays Firestore-agnostic and testable), epoch millis, or a `DateTime`.
DateTime? _parseTime(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  try {
    return (v as dynamic).toDate() as DateTime;
  } catch (_) {
    return null;
  }
}

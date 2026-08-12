/// Feed posts. Three kinds give the feed its rhythm (big milestone cards,
/// medium streak cards, tiny session logs); a sealed hierarchy parsed by `type`
/// lets the feed switch on the kind cleanly. All share an author, timestamp,
/// optional caption and a list of attached [photos], and an `audience` (the
/// author's accepted friends at post time + self) that scopes who can read it —
/// see the friends-only feed rules.
enum PostType { milestone, streak, session }

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
  const PostPhoto({required this.url, required this.storagePath});

  final String url;
  final String storagePath;

  Map<String, dynamic> toMap() => {'url': url, 'storagePath': storagePath};

  factory PostPhoto.fromMap(Map<String, dynamic> map) => PostPhoto(
    url: (map['url'] as String?) ?? '',
    storagePath: (map['storagePath'] as String?) ?? '',
  );

  /// Value equality so a photo list round-trips (write → read → equal).
  @override
  bool operator ==(Object other) =>
      other is PostPhoto &&
      other.url == url &&
      other.storagePath == storagePath;

  @override
  int get hashCode => Object.hash(url, storagePath);
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
        );
      case 'streak':
        return StreakPost(
          id: id,
          authorUid: authorUid,
          author: author,
          createdAt: createdAt,
          caption: caption,
          photos: photos,
          likeCount: likeCount,
          commentCount: commentCount,
          streakDays: _int(map['streakDays']),
          habits: ((map['habits'] as List?) ?? const [])
              .map((e) => '$e')
              .toList(),
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
  });

  final String taskName;

  /// The milestone band reached (20, 40, 60, …).
  final int milestoneHours;

  /// Lifetime hours on the task at post time.
  final int totalHours;

  @override
  PostType get type => PostType.milestone;
}

/// Habit streak — the hero is the streak number, habit list as small print.
///
// TODO(later): StreakPost is not produced by any flow yet — there is no create
// path wiring it (habit-streak posts are a planned stage). Kept in the sealed
// hierarchy so the feed's exhaustive switch stays honest.
class StreakPost extends Post {
  const StreakPost({
    required super.id,
    required super.authorUid,
    required super.author,
    required super.createdAt,
    required super.caption,
    super.photos,
    super.likeCount,
    super.commentCount,
    required this.streakDays,
    required this.habits,
  });

  final int streakDays;
  final List<String> habits;

  @override
  PostType get type => PostType.streak;
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
  });

  final String taskName;
  final int sessionSeconds;

  @override
  PostType get type => PostType.session;
}

int _int(dynamic v) => v is num ? v.toInt() : 0;

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

/// Feed posts. Three kinds give the feed its rhythm (big milestone cards,
/// medium streak cards, tiny session logs); a sealed hierarchy parsed by `type`
/// lets the feed switch on the kind cleanly. All share an author, timestamp,
/// optional caption and optional photo, and an `audience` (the author's accepted
/// friends at post time + self) that scopes who can read it — see the
/// friends-only feed rules.
enum PostType { milestone, streak, session }

/// Denormalized author identity stored on each post so the feed renders without
/// extra profile reads (which the rules keep private).
class PostAuthor {
  const PostAuthor({required this.username, required this.displayName});

  final String username;
  final String displayName;

  String get label => displayName.isNotEmpty ? displayName : '@$username';

  Map<String, dynamic> toMap() => {'username': username, 'displayName': displayName};

  factory PostAuthor.fromMap(Map<String, dynamic> map) => PostAuthor(
        username: (map['username'] as String?) ?? '',
        displayName: (map['displayName'] as String?) ?? '',
      );
}

sealed class Post {
  const Post({
    required this.id,
    required this.authorUid,
    required this.author,
    required this.createdAt,
    required this.caption,
    required this.photoUrl,
  });

  final String id;
  final String authorUid;
  final PostAuthor author;

  /// Null only briefly between a local write and the server timestamp landing.
  final DateTime? createdAt;
  final String? caption;
  final String? photoUrl;

  PostType get type;

  factory Post.fromMap(String id, Map<String, dynamic> map) {
    final author = PostAuthor.fromMap(
        Map<String, dynamic>.from((map['author'] as Map?) ?? const {}));
    final authorUid = (map['authorUid'] as String?) ?? '';
    final createdAt = _parseTime(map['createdAt']);
    final caption = map['caption'] as String?;
    final photoUrl = map['photoUrl'] as String?;

    switch (map['type']) {
      case 'milestone':
        return MilestonePost(
          id: id,
          authorUid: authorUid,
          author: author,
          createdAt: createdAt,
          caption: caption,
          photoUrl: photoUrl,
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
          photoUrl: photoUrl,
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
          photoUrl: photoUrl,
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
    required super.photoUrl,
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
class StreakPost extends Post {
  const StreakPost({
    required super.id,
    required super.authorUid,
    required super.author,
    required super.createdAt,
    required super.caption,
    required super.photoUrl,
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
    required super.photoUrl,
    required this.taskName,
    required this.sessionSeconds,
  });

  final String taskName;
  final int sessionSeconds;

  @override
  PostType get type => PostType.session;
}

int _int(dynamic v) => v is num ? v.toInt() : 0;

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

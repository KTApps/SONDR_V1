import 'post.dart' show PostAuthor;

/// A comment on a post, stored at `posts/{postId}/comments/{commentId}`. Author
/// identity is denormalized (reusing [PostAuthor]) so the thread renders without
/// extra profile reads.
class Comment {
  const Comment({
    required this.id,
    required this.authorUid,
    required this.author,
    required this.text,
    required this.createdAt,
  });

  final String id;
  final String authorUid;
  final PostAuthor author;
  final String text;
  final DateTime? createdAt;

  factory Comment.fromMap(String id, Map<String, dynamic> map) {
    final author = PostAuthor.fromMap(
        Map<String, dynamic>.from((map['author'] as Map?) ?? const {}));
    final raw = map['createdAt'];
    DateTime? createdAt;
    if (raw is DateTime) {
      createdAt = raw;
    } else if (raw is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(raw);
    } else if (raw != null) {
      try {
        createdAt = (raw as dynamic).toDate() as DateTime;
      } catch (_) {
        createdAt = null;
      }
    }
    return Comment(
      id: id,
      authorUid: (map['authorUid'] as String?) ?? '',
      author: author,
      text: (map['text'] as String?) ?? '',
      createdAt: createdAt,
    );
  }
}

import 'package:flutter/foundation.dart';

import 'models/comment.dart';

/// Comments as a thread: each top-level comment, then its replies under
/// it, in time order. One level only.
///
/// Pure, so the ordering, the parent resolution and the depth cap are
/// tested without a widget or a database.
@immutable
class ThreadEntry {
  const ThreadEntry(this.comment, {required this.depth});

  final Comment comment;

  /// 0 for a comment, 1 for a reply. Never more.
  final int depth;

  @override
  bool operator ==(Object other) =>
      other is ThreadEntry && other.comment.id == comment.id && other.depth == depth;

  @override
  int get hashCode => Object.hash(comment.id, depth);
}

/// [comments] in any order → the thread. A reply whose parent is gone
/// (deleted, or pruned out of the reader's audience) is shown as a
/// top-level comment rather than lost: what someone wrote is still
/// theirs to see.
List<ThreadEntry> threadOf(List<Comment> comments) {
  int by(Comment a, Comment b) {
    final x = a.createdAt, y = b.createdAt;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return x.compareTo(y);
  }

  final sorted = [...comments]..sort(by);
  final ids = {for (final c in sorted) c.id};
  final replies = <String, List<Comment>>{};
  final tops = <Comment>[];
  for (final c in sorted) {
    final parent = c.parentId;
    if (parent != null && ids.contains(parent)) {
      (replies[parent] ??= []).add(c);
    } else {
      tops.add(c);
    }
  }
  return [
    for (final t in tops) ...[
      ThreadEntry(t, depth: 0),
      for (final r in replies[t.id] ?? const <Comment>[]) ThreadEntry(r, depth: 1),
    ],
  ];
}

/// The parent a reply to [target] should name: the target itself when it
/// is top-level, otherwise ITS parent — a reply to a reply attaches to the
/// same parent, never deeper.
String replyParentOf(Comment target) => target.parentId ?? target.id;

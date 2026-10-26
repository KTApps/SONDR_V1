import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/features/feed/comment_threads.dart';
import 'package:sondr/features/feed/models/comment.dart';
import 'package:sondr/features/feed/models/post.dart';

/// Comments as a thread: parents, their replies under them, one level.
void main() {
  const who = PostAuthor(username: 'tom', displayName: 'Tom');
  Comment c(String id, int minute, {String? parent}) => Comment(
    id: id,
    authorUid: 'u',
    author: who,
    text: id,
    createdAt: DateTime(2026, 10, 1, 9, minute),
    parentId: parent,
  );

  test('replies sit under their parent, in time order', () {
    final thread = threadOf([
      c('r2', 5, parent: 'a'),
      c('b', 3),
      c('a', 1),
      c('r1', 2, parent: 'a'),
    ]);
    expect(thread.map((e) => '${e.comment.id}:${e.depth}'), [
      'a:0', 'r1:1', 'r2:1', 'b:0',
    ]);
  });

  test('a reply whose parent is gone is shown, not lost', () {
    final thread = threadOf([c('orphan', 2, parent: 'deleted'), c('a', 1)]);
    expect(thread.map((e) => '${e.comment.id}:${e.depth}'), ['a:0', 'orphan:0']);
  });

  test('depth never exceeds one', () {
    final thread = threadOf([c('a', 1), c('r', 2, parent: 'a'), c('rr', 3, parent: 'a')]);
    expect(thread.every((e) => e.depth <= 1), isTrue);
  });

  test('replying to a reply names the same parent', () {
    expect(replyParentOf(c('a', 1)), 'a');
    expect(replyParentOf(c('r', 2, parent: 'a')), 'a');
  });

  test('a comment with no time yet sorts last, not nowhere', () {
    final late = Comment(id: 'new', authorUid: 'u', author: who, text: 'x', createdAt: null);
    final thread = threadOf([late, c('a', 1)]);
    expect(thread.map((e) => e.comment.id), ['a', 'new']);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/widgets/deletable_post_card.dart';

const _author = PostAuthor(username: 'x', displayName: 'X');

SessionPost _post({
  required String authorUid,
  List<PostPhoto> photos = const [],
}) => SessionPost(
  id: 'p1',
  authorUid: authorUid,
  author: _author,
  createdAt: DateTime(2026, 6, 1),
  caption: null,
  photos: photos,
  taskName: 'T',
  sessionSeconds: 3600,
);

Future<void> _pump(
  WidgetTester tester, {
  required String? viewerUid,
  required Post post,
  Future<void> Function(Post)? onDelete,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [currentUidProvider.overrideWithValue(viewerUid)],
    child: MaterialApp(
      home: Scaffold(
        body: DeletablePostCard(
          post: post,
          onDelete: onDelete,
          // A realistic slim-card footprint (feed width) so the side-by-side
          // Delete/Close row has room, as it does on a real device.
          child: const SizedBox(height: 80, width: 360),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('own post: long-press reveals Delete + Close', (tester) async {
    await _pump(
      tester,
      viewerUid: 'me',
      post: _post(authorUid: 'me'),
    );
    await tester.longPress(find.byType(DeletablePostCard));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets("someone else's post: long-press does nothing", (tester) async {
    await _pump(
      tester,
      viewerUid: 'me',
      post: _post(authorUid: 'not-me'),
    );
    await tester.longPress(find.byType(DeletablePostCard));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Close'), findsNothing);
  });

  testWidgets('no viewer uid (logged out): long-press does nothing', (
    tester,
  ) async {
    await _pump(tester, viewerUid: null, post: _post(authorUid: 'me'));
    await tester.longPress(find.byType(DeletablePostCard));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('Delete invokes deletePost with the post (un-share path)', (
    tester,
  ) async {
    final post = _post(authorUid: 'me');
    Post? deleted;
    await _pump(
      tester,
      viewerUid: 'me',
      post: post,
      onDelete: (p) async => deleted = p,
    );
    await tester.longPress(find.byType(DeletablePostCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted, same(post));
  });

  testWidgets('Close un-reveals the overlay', (tester) async {
    await _pump(
      tester,
      viewerUid: 'me',
      post: _post(authorUid: 'me'),
    );
    await tester.longPress(find.byType(DeletablePostCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
  });
}

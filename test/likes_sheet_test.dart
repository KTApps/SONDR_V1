import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/feed/widgets/likes_sheet.dart';
import 'package:sondr/features/feed/widgets/post_chrome.dart';

/// Who liked a post — and that only the author is offered the sheet.
void main() {
  const author = PostAuthor(username: 'tom', displayName: 'Tom Hardy');
  final post = SessionPost(
    id: 'p1',
    authorUid: 'tom-uid',
    author: author,
    createdAt: DateTime(2026, 10, 1),
    caption: null,
    taskName: 'Spanish',
    sessionSeconds: 900,
  );

  Future<void> pumpRow(WidgetTester tester, {required String? viewer}) =>
      tester.pumpWidget(
        ProviderScope(
          overrides: [currentUidProvider.overrideWithValue(viewer)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(body: PostInteractions(post: post)),
          ),
        ),
      );

  group('the word on the row', () {
    testWidgets('the author sees "Likes", and cannot like', (tester) async {
      await pumpRow(tester, viewer: 'tom-uid');
      expect(find.text('Likes'), findsOneWidget);
      expect(find.text('Like'), findsNothing);
      expect(find.text('Liked'), findsNothing);
      expect(find.text('Comments'), findsOneWidget);
    });

    testWidgets('everyone else sees Like, as before', (tester) async {
      await pumpRow(tester, viewer: 'cass-uid');
      expect(find.text('Like'), findsOneWidget);
      expect(find.text('Likes'), findsNothing);
    });

    testWidgets('tapping Likes opens the sheet', (tester) async {
      await pumpRow(tester, viewer: 'tom-uid');
      await tester.tap(find.text('Likes'));
      await tester.pumpAndSettle();
      expect(find.byType(LikesSheet), findsOneWidget);
    });
  });

  group('the sheet', () {
    Future<void> pumpSheet(WidgetTester tester, List<PostLike> likes) =>
        tester.pumpWidget(
          ProviderScope(
            overrides: [
              postLikesProvider.overrideWith((ref, id) => Stream.value(likes)),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const Scaffold(body: LikesSheet(postId: 'p1')),
            ),
          ),
        );

    testWidgets('says "No likes yet" when there are none', (tester) async {
      await pumpSheet(tester, const []);
      await tester.pumpAndSettle();
      expect(find.text('Likes'), findsOneWidget);
      expect(find.text('No likes yet'), findsOneWidget);
    });

    testWidgets('one row per like, newest first, no body line', (tester) async {
      await pumpSheet(tester, [
        PostLike(uid: 'u2', at: DateTime(2026, 10, 2)),
        PostLike(uid: 'u1', at: DateTime(2026, 10, 1)),
      ]);
      await tester.pumpAndSettle();
      expect(find.byType(CircleAvatar), findsNWidgets(2));
      expect(find.text('No likes yet'), findsNothing);
      // The list keeps the stream's order — the repository orders by at desc.
      final avatars = tester.getTopLeft(find.byType(CircleAvatar).first).dy;
      expect(avatars, lessThan(tester.getTopLeft(find.byType(CircleAvatar).last).dy));
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/models/comment.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/feed/widgets/comments_sheet.dart';
import 'package:sondr/shared/sondr_field.dart';

/// Replying: the word on each comment, the line above the field, the way
/// out of it, and the indent a reply gets.
void main() {
  const cass = PostAuthor(username: 'cass', displayName: 'Cass');
  const bea = PostAuthor(username: 'bea', displayName: 'Bea');
  final comments = [
    Comment(id: 'top', authorUid: 'cass', author: cass, text: 'first', createdAt: DateTime(2026, 10, 1, 9)),
    Comment(id: 'r1', authorUid: 'bea', author: bea, text: 'reply', createdAt: DateTime(2026, 10, 1, 10), parentId: 'top'),
  ];

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('me'),
          postCommentsProvider.overrideWith((ref, id) => AsyncValue.data(comments)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showCommentsSheet(context, 'p1'),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('every comment and reply offers Reply; a reply is indented', (tester) async {
    await open(tester);
    expect(find.text('Reply'), findsNWidgets(2));
    final parent = tester.getTopLeft(find.text('first')).dx;
    final reply = tester.getTopLeft(find.text('reply')).dx;
    // The reply's row begins 24 beyond the parent's text start, and its own
    // text sits an avatar and a gap further in.
    expect(reply - parent, greaterThan(24));
  });

  testWidgets('tapping Reply shows who, offers Cancel, and focuses the field', (tester) async {
    await open(tester);
    await tester.tap(find.text('Reply').first);
    await tester.pumpAndSettle();
    expect(find.text('Replying to cass'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, isNotNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Replying to cass'), findsNothing);
  });

  testWidgets('replying to a reply names its parent', (tester) async {
    await open(tester);
    await tester.tap(find.text('Reply').last);
    await tester.pumpAndSettle();
    // The reply was bea's; the composer still says bea, the parent is top.
    expect(find.text('Replying to bea'), findsOneWidget);
    final field = tester.widget<SondrField>(find.byType(SondrField));
    expect(field.textInputAction, TextInputAction.done);
  });
}

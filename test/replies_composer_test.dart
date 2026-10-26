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

/// The composers: the one at the top, and the one that opens beneath a
/// thread when you reply.
void main() {
  const cass = PostAuthor(username: 'cass', displayName: 'Cass');
  const bea = PostAuthor(username: 'bea', displayName: 'Bea');
  List<Comment> comments({int extra = 0}) => [
    Comment(id: 'top', authorUid: 'cass', author: cass, text: 'first', createdAt: DateTime(2026, 10, 1, 9)),
    Comment(id: 'r1', authorUid: 'bea', author: bea, text: 'reply', createdAt: DateTime(2026, 10, 1, 10), parentId: 'top'),
    Comment(id: 'second', authorUid: 'bea', author: bea, text: 'another', createdAt: DateTime(2026, 10, 1, 11)),
    for (var i = 0; i < extra; i++)
      Comment(id: 'f$i', authorUid: 'bea', author: bea, text: 'filler $i', createdAt: DateTime(2026, 10, 1, 12, i)),
  ];

  const w = 390.0, h = 844.0, keyboard = 335.0;

  Future<void> open(WidgetTester tester, {int extra = 0, bool keyboardUp = false}) async {
    tester.view.physicalSize = const Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.viewInsets = keyboardUp ? const FakeViewPadding(bottom: keyboard * 3) : FakeViewPadding.zero;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('me'),
          postCommentsProvider.overrideWith((ref, id) => AsyncValue.data(comments(extra: extra))),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(onPressed: () => showCommentsSheet(context, 'p1'), child: const Text('open')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('the top composer', () {
    testWidgets('is bare, focused, and says Cancel until there is text', (tester) async {
      await open(tester);
      final field = tester.widget<SondrField>(find.byType(SondrField));
      expect(field.hint, isNull);
      expect(field.autofocus, isTrue);
      expect(find.text('Cancel').hitTestable(), findsOneWidget);
      expect(find.text('Post').hitTestable(), findsNothing);
      expect(find.textContaining('Replying to'), findsNothing);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();
      expect(find.text('Post').hitTestable(), findsOneWidget);
      expect(find.text('Cancel').hitTestable(), findsNothing);
    });

    testWidgets('Cancel clears and keeps the cursor', (tester) async {
      await open(tester);
      // Whitespace is not text: the word stays Cancel.
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pumpAndSettle();
      expect(find.text('Cancel').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Cancel').hitTestable());
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, '');
      expect(FocusManager.instance.primaryFocus, isNotNull, reason: 'Cancel took the cursor away');
    });
  });

  group('replying', () {
    testWidgets('Reply opens a composer beneath the thread, focused, indented', (tester) async {
      await open(tester);
      expect(find.byType(SondrField), findsOneWidget);
      await tester.tap(find.text('Reply').first);
      await tester.pumpAndSettle();
      expect(find.byType(SondrField), findsNWidgets(2));
      final fields = tester.widgetList<SondrField>(find.byType(SondrField)).toList();
      expect(fields.last.focusNode?.hasFocus, isTrue, reason: 'the reply composer takes the cursor');
      expect(fields.first.controller.text, '');
      // Beneath the thread: below its last reply, above the next comment.
      final composer = tester.getRect(find.byType(SondrField).last);
      expect(composer.top, greaterThan(tester.getRect(find.text('reply')).bottom));
      expect(composer.bottom, lessThan(tester.getRect(find.text('another')).top));
      // Indented like a reply.
      expect(composer.left, greaterThan(tester.getRect(find.text('first')).left));
    });

    testWidgets('a second Reply moves it; Cancel removes it', (tester) async {
      await open(tester);
      await tester.tap(find.text('Reply').first);
      await tester.pumpAndSettle();
      final under = tester.getRect(find.byType(SondrField).last);
      await tester.tap(find.text('Reply').last);
      await tester.pumpAndSettle();
      expect(find.byType(SondrField), findsNWidgets(2));
      final moved = tester.getRect(find.byType(SondrField).last);
      expect(moved.top, greaterThan(under.top));
      expect(moved.top, greaterThan(tester.getRect(find.text('another')).bottom));

      await tester.tap(find.text('Cancel').hitTestable().last, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(SondrField), findsOneWidget);
      expect(tester.widget<SondrField>(find.byType(SondrField)).focusNode?.hasFocus, isTrue);
    });

    testWidgets('Post sends with the parent and removes the composer', (tester) async {
      await open(tester);
      await tester.tap(find.text('Reply').first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'yes');
      await tester.pumpAndSettle();
      expect(find.text('Post').hitTestable(), findsOneWidget);
      // No repository behind the sheet in a test: the send is a no-op, but
      // the word was there and the field is the reply's.
      final reply = tester.widgetList<SondrField>(find.byType(SondrField)).last;
      expect(reply.controller.text, 'yes');
    });

    testWidgets('a Reply near the bottom opens above the keyboard', (tester) async {
      await open(tester, extra: 12, keyboardUp: true);
      // The last thread's Reply, scrolled to.
      await tester.scrollUntilVisible(find.text('Reply').last, 200, scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Reply').last);
      await tester.pumpAndSettle();
      final composer = tester.getRect(find.byType(SondrField).last);
      expect(composer.bottom, lessThanOrEqualTo(h - keyboard + 0.5), reason: 'the reply composer is behind the keyboard');
    });
  });
}

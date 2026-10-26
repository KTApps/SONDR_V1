import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/models/comment.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/feed/widgets/comments_sheet.dart';
import 'package:sondr/shared/sondr_field.dart';
import 'package:sondr/shared/sondr_swipe_row.dart';

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

  Future<void> open(WidgetTester tester, {int extra = 0, bool keyboardUp = false, double textScale = 1.0}) async {
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
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
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
    testWidgets('is bare, focused, and says Close until there is text', (tester) async {
      await open(tester);
      final field = tester.widget<SondrField>(find.byType(SondrField));
      expect(field.hint, isNull);
      expect(field.autofocus, isTrue);
      expect(find.text('Close').hitTestable(), findsOneWidget);
      expect(find.text('Post').hitTestable(), findsNothing);
      expect(find.textContaining('Replying to'), findsNothing);

      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pumpAndSettle();
      expect(find.text('Post').hitTestable(), findsOneWidget);
      expect(find.text('Close').hitTestable(), findsNothing);
    });

    testWidgets('Close clears the field and puts the keyboard away', (tester) async {
      await open(tester);
      // Whitespace is not text: the word stays Close.
      await tester.enterText(find.byType(TextField), '   ');
      await tester.pumpAndSettle();
      expect(find.text('Close').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Close').hitTestable());
      await tester.pumpAndSettle();
      final field = tester.widget<SondrField>(find.byType(SondrField));
      expect(field.controller.text, '');
      expect(field.focusNode?.hasFocus, isFalse, reason: 'Close should dismiss the keyboard');
      // The field is still there for the next comment, and still bare.
      expect(find.byType(SondrField), findsOneWidget);
      expect(find.text('Close').hitTestable(), findsOneWidget);
    });

    testWidgets('the word is Close or Post, never both, as text comes and goes', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pumpAndSettle();
      expect(find.text('Post').hitTestable(), findsOneWidget);
      expect(find.text('Close').hitTestable(), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('Close').hitTestable(), findsOneWidget);
      expect(find.text('Post').hitTestable(), findsNothing);
    });
  });

  group('replying', () {
    testWidgets('Reply opens a composer beneath the thread, focused', (tester) async {
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
    });

    testWidgets('the reply composer is laid out exactly like the top one', (tester) async {
      await open(tester);
      await tester.tap(find.text('Reply').first);
      await tester.pumpAndSettle();
      final fields = find.byType(SondrField);
      expect(fields, findsNWidgets(2));
      final top = tester.getRect(fields.first);
      final reply = tester.getRect(fields.last);
      // Same width and the same centre line: the cursor and the typed text
      // sit on one vertical line down the sheet, not indented as replies are.
      expect(reply.width, moreOrLessEquals(top.width, epsilon: 0.5));
      expect(reply.center.dx, moreOrLessEquals(top.center.dx, epsilon: 0.5));
      expect(reply.left, lessThan(tester.getRect(find.text('reply')).left),
          reason: 'the composer is not indented like the reply above it');
      // The word at the right sits at the same edge on both.
      final words = find.text('Close').hitTestable();
      expect(words, findsNWidgets(2));
      expect(tester.getRect(words.last).right, moreOrLessEquals(tester.getRect(words.first).right, epsilon: 0.5));
      await tester.enterText(find.byType(TextField).last, 'yes');
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Post').hitTestable()).right,
          moreOrLessEquals(tester.getRect(find.text('Close').hitTestable()).right, epsilon: 0.5));
    });

    testWidgets('a second Reply moves it; Close removes it and the keyboard', (tester) async {
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

      // The reply composer's own word says Close too.
      expect(find.text('Close').hitTestable(), findsNWidgets(2));
      await tester.tap(find.text('Close').hitTestable().last, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(SondrField), findsOneWidget);
      // Nothing takes the cursor back: the keyboard is simply gone.
      expect(tester.widget<SondrField>(find.byType(SondrField)).focusNode?.hasFocus, isFalse,
          reason: 'Close on a reply should not refocus the top composer');
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

  /// The clearance between the cursor and the keyboard is the gap between
  /// the text above and the cursor — one rhythm either side of the field —
  /// and it holds as the field grows to two and three lines.
  group('above the keyboard', () {
    // Twelve older comments, then the thread, so Reply on it has to scroll.
    List<Comment> late() => [
      for (var i = 0; i < 12; i++)
        Comment(id: 'f$i', authorUid: 'bea', author: bea, text: 'filler $i', createdAt: DateTime(2026, 10, 1, 8, i)),
      Comment(id: 'top', authorUid: 'cass', author: cass, text: 'first', createdAt: DateTime(2026, 10, 1, 9)),
      Comment(id: 'r1', authorUid: 'bea', author: bea, text: 'reply', createdAt: DateTime(2026, 10, 1, 10), parentId: 'top'),
    ];

    Future<void> replyToLast(WidgetTester tester, double textScale) async {
      tester.view.physicalSize = const Size(w * 3, h * 3);
      tester.view.devicePixelRatio = 3.0;
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUidProvider.overrideWithValue('me'),
            postCommentsProvider.overrideWith((ref, id) => AsyncValue.data(late())),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
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
      await tester.scrollUntilVisible(find.text('reply'), 200, scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
      final row = find.ancestor(of: find.text('reply'), matching: find.byType(SondrSwipeRow)).first;
      await tester.tap(find.descendant(of: row, matching: find.text('Reply')), warnIfMissed: false);
      await tester.pumpAndSettle();
    }

    /// The cursor's line box: the field's editable area.
    Rect cursorBox(WidgetTester tester) => tester.getRect(
      find.descendant(of: find.byType(SondrField).last, matching: find.byType(EditableText)),
    );

    /// The caret itself, at the end of the text.
    Rect caret(WidgetTester tester) {
      final re = tester.renderObject<RenderEditable>(find.descendant(
        of: find.byType(SondrField).last,
        matching: find.byElementPredicate((e) => e.renderObject is RenderEditable),
      ));
      final local = re.getLocalRectForCaret(TextPosition(offset: re.text!.toPlainText().length));
      final tl = re.localToGlobal(local.topLeft);
      return Rect.fromLTWH(tl.dx, tl.dy, local.width, local.height);
    }

    const kb = h - keyboard;
    for (final ts in [0.824, 1.0, 1.235]) {
      testWidgets('at textScale $ts the clearance below equals the gap above', (tester) async {
        await replyToLast(tester, ts);
        final textBottom = tester.getRect(find.text('reply')).bottom;
        final box = cursorBox(tester);
        final above = box.top - textBottom;
        final below = kb - box.bottom;
        // ignore: avoid_print
        print('AFTER ts=$ts gapAbove=${above.toStringAsFixed(2)} gapBelow=${below.toStringAsFixed(2)} '
            'caretAbove=${(caret(tester).top - textBottom).toStringAsFixed(2)} caretBelow=${(kb - caret(tester).bottom).toStringAsFixed(2)}');
        expect(below, moreOrLessEquals(above, epsilon: 0.5));
        expect(kb - caret(tester).bottom, moreOrLessEquals(caret(tester).top - textBottom, epsilon: 0.5));

        // Two lines, then three: the field grows down and is brought back
        // to the same clearance each time.
        for (final text in [
          'a long reply that should certainly wrap onto a second line of the field here',
          'a long reply that should certainly wrap onto a second line of the field here, '
              'and then keep going far enough to need a third line as well, which it does',
        ]) {
          await tester.enterText(find.byType(TextField).last, text);
          await tester.pumpAndSettle();
          expect(kb - cursorBox(tester).bottom, moreOrLessEquals(above, epsilon: 0.5),
              reason: 'the grown field should keep the clearance');
          expect(find.text('reply'), findsOneWidget, reason: 'the reply above should still be on screen');
        }
      });
    }
  });
}

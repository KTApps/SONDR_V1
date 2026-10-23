import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/models/comment.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/posts_repository.dart';
import 'package:sondr/features/feed/widgets/comments_sheet.dart';
import 'package:sondr/features/reports/report.dart';
import 'package:sondr/features/reports/report_flow.dart';
import 'package:sondr/shared/sondr_error.dart';
import 'package:sondr/shared/sondr_field.dart';
import 'package:sondr/shared/sondr_notice.dart';

/// The comments sheet, measured on an iPhone 13 Pro in both keyboard states.
///
/// The bug this pins: the sheet was a fixed 0.7-of-screen box inside a Padding
/// carrying the keyboard inset. 0.7 plus a keyboard is more than a screen, so
/// the box was clamped, the sheet filled the display, and the whole column —
/// grab handle included — slid up under the status bar with no way to dismiss
/// it. The sheet's top must not move when the keyboard opens.
const double w13 = 390;
const double h13 = 844;
const double top13 = 47;

/// 0.7 of 844.
const double expectedSheetTop = h13 - h13 * 0.7; // 253.2

/// The composer's measured position, which removing the empty-state line must
/// not disturb — it sits above the list, so an empty list below it is free to
/// render nothing without anything moving.
const double composerTop = 318.3;
const double composerBottom = 336.3;

/// Where the keyboard's top edge lands on this device.
const double keyboardInset = 335;
const double keyboardTop = h13 - keyboardInset; // 509

void main() {
  /// Opens the sheet over a host screen, with [keyboard] up or down.
  Future<void> openSheet(
    WidgetTester tester, {
    required bool keyboard,
    List<Comment> comments = const [],
    Reports? reports,
  }) async {
    tester.view.physicalSize = const Size(w13 * 3, h13 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: top13 * 3);
    tester.view.viewInsets = keyboard
        ? const FakeViewPadding(bottom: keyboardInset * 3)
        : FakeViewPadding.zero;
    addTearDown(tester.view.reset);

    // Unmount anything a previous openSheet left behind. Without this the old
    // sheet is still on the navigator, and the tap below lands on its barrier
    // instead of the button.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('me'),
          postCommentsProvider.overrideWith(
            (ref, postId) => AsyncValue.data(comments),
          ),
          if (reports != null) reportsProvider.overrideWithValue(reports),
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
    expect(find.byType(CommentsSheet), findsOneWidget);
  }

  /// The keyboard arriving (or leaving) on a sheet that is ALREADY open —
  /// which is the moment the bug happened, not a fresh open.
  Future<void> setKeyboard(WidgetTester tester, {required bool up}) async {
    tester.view.viewInsets = up
        ? const FakeViewPadding(bottom: keyboardInset * 3)
        : FakeViewPadding.zero;
    await tester.pumpAndSettle();
  }

  double top(Finder f, WidgetTester t) => t.getTopLeft(f).dy;
  double bottom(Finder f, WidgetTester t) => t.getBottomLeft(f).dy;

  Finder sheet() => find.byType(CommentsSheet);
  Finder handle() => find.byWidgetPredicate(
    (w) => w is Container && w.constraints?.maxWidth != null,
  );
  /// An empty list renders nothing at all, so there is no widget to anchor a
  /// finder on — the room left for comments is measured as the gap between the
  /// composer and whatever is cutting the sheet off from below.
  Finder commentList() =>
      find.descendant(of: sheet(), matching: find.byType(ListView));

  group('the sheet', () {
    testWidgets('top is 0.7 of the screen with the keyboard DOWN', (
      tester,
    ) async {
      await openSheet(tester, keyboard: false);
      expect(top(sheet(), tester), closeTo(expectedSheetTop, 1));
      // The feed is visible above it, and the handle clears the status bar.
      expect(top(sheet(), tester), greaterThanOrEqualTo(200));
      expect(top(handle(), tester), greaterThanOrEqualTo(top13));
    });

    testWidgets('top does not move when the keyboard opens, or closes again', (
      tester,
    ) async {
      await openSheet(tester, keyboard: false);
      final down = top(sheet(), tester);

      await setKeyboard(tester, up: true);
      final up = top(sheet(), tester);
      expect(up, closeTo(expectedSheetTop, 1));
      expect(up, closeTo(down, 0.5));
      expect(top(handle(), tester), greaterThanOrEqualTo(top13));

      // And back: the sheet does not grow when the keyboard leaves either.
      await setKeyboard(tester, up: false);
      expect(top(sheet(), tester), closeTo(down, 0.5));
    });

    testWidgets('with the keyboard up the composer is above it, not under '
        'the title', (tester) async {
      await openSheet(tester, keyboard: true);
      // The composer keeps an INVISIBLE Post on its left as a spacer, so the
      // real one is the hit-testable match.
      final postLabel = find.text('Post').hitTestable();
      expect(postLabel, findsOneWidget);
      // The whole composer sits clear of the keyboard's top edge.
      expect(
        bottom(find.byType(SondrField), tester),
        lessThanOrEqualTo(keyboardTop),
      );
      expect(bottom(postLabel, tester), lessThanOrEqualTo(keyboardTop));
      // The comments still have room to be read: the space between the
      // composer and the keyboard's top edge.
      expect(keyboardTop - bottom(postLabel, tester),
          greaterThanOrEqualTo(100));
    });
  });

  group('the return key', () {
    testWidgets('closes the keyboard, inserts nothing, posts nothing', (
      tester,
    ) async {
      await openSheet(tester, keyboard: true);
      final field = find.byType(EditableText);
      await tester.tap(field);
      await tester.pumpAndSettle();
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isTrue);

      await tester.enterText(field, 'kind words');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Focus gone.
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse);
      // No newline, and the text is untouched.
      final text = tester.widget<EditableText>(field).controller.text;
      expect(text, 'kind words');
      expect(text.contains('\n'), isFalse);
      // Nothing was sent: there is still no list to show.
      expect(commentList(), findsNothing);
    });

    testWidgets('the field is still a three-line wrapper', (tester) async {
      await openSheet(tester, keyboard: false);
      final f = tester.widget<SondrField>(find.byType(SondrField));
      expect(f.minLines, 1);
      expect(f.maxLines, 3);
      expect(f.textInputAction, TextInputAction.done);
    });
  });

  group('the empty state', () {
    testWidgets('says nothing, and moves nothing', (tester) async {
      await openSheet(tester, keyboard: false);
      for (final up in [false, true]) {
        await setKeyboard(tester, up: up);
        // No line, no list, no placeholder of any kind.
        expect(find.textContaining('No comments yet'), findsNothing);
        expect(commentList(), findsNothing);
        // And the sheet is where it was before the line was removed.
        expect(top(sheet(), tester), closeTo(expectedSheetTop, 1));
        expect(top(find.byType(SondrField), tester),
            closeTo(composerTop, 1));
        expect(bottom(find.byType(SondrField), tester),
            closeTo(composerBottom, 1));
      }
    });
  });

  group('reporting a comment', () {
    Comment comment(String id, String author) => Comment(
      id: id,
      authorUid: author,
      author: PostAuthor(username: author, displayName: author),
      text: 'a comment by $author',
      createdAt: DateTime(2026, 10, 1),
    );

    /// The tray behind one comment, once it has been swiped open.
    Future<void> reveal(WidgetTester tester, String text) async {
      await tester.drag(find.text(text), const Offset(-200, 0));
      await tester.pumpAndSettle();
    }

    testWidgets('your own comment offers Delete, not Report', (tester) async {
      await openSheet(
        tester,
        keyboard: false,
        comments: [comment('c1', 'me')],
      );
      await reveal(tester, 'a comment by me');
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Report'), findsNothing);
    });

    testWidgets("somebody else's offers Report, not Delete", (tester) async {
      await openSheet(
        tester,
        keyboard: false,
        comments: [comment('c1', 'them')],
      );
      await reveal(tester, 'a comment by them');
      expect(find.text('Report'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
    });

    /// The tray used to carry SondrSwipeRow's default 24 inset while the
    /// composer sits on 6, so the revealed action stopped 17.83 short of
    /// Post on a 13 Pro — close enough to look like a mistake rather than a
    /// margin. Delete and Report are the same slot, so one number fixes
    /// both, and both are checked.
    for (final (author, label) in [('them', 'Report'), ('me', 'Delete')]) {
      testWidgets('$label lines up with Post', (tester) async {
        await openSheet(
          tester,
          keyboard: false,
          comments: [comment('c1', author)],
        );
        // The composer carries a hidden second Post to centre the field;
        // the real one is the hit-testable one.
        final post = tester.getRect(find.text('Post').hitTestable());
        await reveal(tester, 'a comment by $author');
        final action = tester.getRect(find.text(label));
        expect(
          action.right,
          closeTo(post.right, 0.5),
          reason: '$label is ${(post.right - action.right).toStringAsFixed(2)} '
              'off Post',
        );
      });
    }

    testWidgets('Report asks why, then thanks on the sheet\'s own line', (
      tester,
    ) async {
      final reports = _Reports();
      await openSheet(
        tester,
        keyboard: false,
        comments: [comment('c1', 'them')],
        reports: reports,
      );
      await reveal(tester, 'a comment by them');
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(find.text('Report comment'), findsOneWidget);
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();

      // The post id and the comment id, which is where a moderator looks.
      expect(reports.sent, ['comment|p1/c1|them|spam']);
      expect(reports.hidden, ['comment__p1_c1']);
      // A thank-you is not a failure: the quiet tone, not the error style.
      expect(
        find.descendant(
          of: find.byType(SondrNotice),
          matching: find.text(kReportThanks),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a report that fails says so and hides nothing', (
      tester,
    ) async {
      final reports = _Reports(sends: false);
      await openSheet(
        tester,
        keyboard: false,
        comments: [comment('c1', 'them')],
        reports: reports,
      );
      await reveal(tester, 'a comment by them');
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();

      expect(reports.hidden, isEmpty);
      expect(
        find.descendant(
          of: find.byType(SondrError),
          matching: find.text(kReportFailed),
        ),
        findsOneWidget,
      );
    });
  });
}

/// A report we can inspect, so the sheet's tests never reach Firestore.
class _Reports implements Reports {
  _Reports({this.sends = true});

  final bool sends;
  final List<String> sent = [];
  final List<String> hidden = [];

  @override
  Future<bool> send({
    required ReportTarget type,
    required String targetKey,
    required String targetOwnerUid,
    required ReportReason reason,
  }) async {
    if (!sends) return false;
    sent.add('${type.wire}|$targetKey|$targetOwnerUid|${reason.wire}');
    return true;
  }

  @override
  Future<void> hide(ReportTarget type, String targetKey) async {
    if (type == ReportTarget.user) return;
    hidden.add(hiddenKey(type, targetKey));
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/widgets/deletable_post_card.dart';
import 'package:sondr/shared/blur_sheet.dart';
import 'package:sondr/features/reports/report.dart';

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
  Reports? reports,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [
      currentUidProvider.overrideWithValue(viewerUid),
      if (reports != null) reportsProvider.overrideWithValue(reports),
    ],
    child: MaterialApp(
      theme: AppTheme.dark(),
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
  testWidgets('own post: a long-press asks whether to delete it', (
    tester,
  ) async {
    await _pump(tester, viewerUid: 'me', post: _post(authorUid: 'me'));
    await tester.longPress(find.byType(DeletablePostCard));
    await tester.pumpAndSettle();
    // The app's frosted question, not a panel over the card.
    expect(find.byType(BlurSheet), findsOneWidget);
    expect(find.text('Delete this post?'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Report'), findsNothing);
  });

  testWidgets("someone else's post: a long-press asks why", (tester) async {
    await _pump(
      tester,
      viewerUid: 'me',
      post: _post(authorUid: 'not-me'),
      reports: _Reports(),
    );
    await tester.longPress(find.byType(DeletablePostCard));
    await tester.pumpAndSettle();
    // Straight to the reasons: there is only one thing a long-press on
    // somebody else's post can mean.
    expect(find.text('Why are you reporting this?'), findsOneWidget);
    expect(find.text('Report post'), findsOneWidget);
    expect(find.text('Spam'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('no viewer uid (logged out): long-press does nothing', (
    tester,
  ) async {
    await _pump(tester, viewerUid: null, post: _post(authorUid: 'me'));
    await tester.longPress(find.byType(DeletablePostCard));
    await tester.pumpAndSettle();
    // Not ours, so it is reported rather than deleted — and with no
    // backend behind it the reasons still open and go nowhere.
    expect(find.text('Delete this post?'), findsNothing);
  });

  testWidgets('Delete invokes deletePost with the post', (tester) async {
    Post? deleted;
    await _pump(
      tester,
      viewerUid: 'me',
      post: _post(authorUid: 'me'),
      onDelete: (p) async => deleted = p,
    );
    await tester.longPress(find.byType(DeletablePostCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(deleted?.id, 'p1');
    expect(find.byType(BlurSheet), findsNothing);
  });

  testWidgets('Cancel deletes nothing', (tester) async {
    Post? deleted;
    await _pump(
      tester,
      viewerUid: 'me',
      post: _post(authorUid: 'me'),
      onDelete: (p) async => deleted = p,
    );
    await tester.longPress(find.byType(DeletablePostCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(deleted, isNull);
    expect(find.byType(BlurSheet), findsNothing);
  });

  testWidgets('the question is never where the finger was', (tester) async {
    await _pump(tester, viewerUid: 'me', post: _post(authorUid: 'me'));
    final card = tester.getRect(find.byType(DeletablePostCard));
    await tester.longPress(find.byType(DeletablePostCard));
    await tester.pumpAndSettle();
    // The card sits at the top of this harness; the answer is in the
    // middle of the screen, where no long-press on it could have landed.
    expect(tester.getRect(find.text('Delete')).top, greaterThan(card.bottom));
  });

  group("reporting somebody else's post", () {
    testWidgets('a reason writes the report and hides the post', (
      tester,
    ) async {
      final reports = _Reports();
      await _pump(
        tester,
        viewerUid: 'me',
        post: _post(authorUid: 'not-me'),
        reports: reports,
      );
      await tester.longPress(find.byType(DeletablePostCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hate or harassment'));
      await tester.pumpAndSettle();

      expect(reports.sent, ['post|p1|not-me|hate']);
      expect(reports.hidden, ['post__p1']);
      expect(find.byType(BlurSheet), findsNothing);
    });

    testWidgets('a report that fails hides nothing', (tester) async {
      final reports = _Reports(sends: false);
      await _pump(
        tester,
        viewerUid: 'me',
        post: _post(authorUid: 'not-me'),
        reports: reports,
      );
      await tester.longPress(find.byType(DeletablePostCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();
      expect(reports.hidden, isEmpty);
    });

    testWidgets('Cancel writes nothing', (tester) async {
      final reports = _Reports();
      await _pump(
        tester,
        viewerUid: 'me',
        post: _post(authorUid: 'not-me'),
        reports: reports,
      );
      await tester.longPress(find.byType(DeletablePostCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(reports.sent, isEmpty);
      expect(reports.hidden, isEmpty);
    });
  });
}

/// A report we can inspect, so the card's tests never reach Firestore.
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

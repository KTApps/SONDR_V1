import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/widgets/deletable_post_card.dart';
import 'package:sondr/features/reports/report.dart';
import 'package:sondr/features/reports/report_flow.dart';

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

  testWidgets("someone else's post: long-press offers Report, not Delete", (
    tester,
  ) async {
    await _pump(
      tester,
      viewerUid: 'me',
      post: _post(authorUid: 'not-me'),
    );
    await tester.longPress(find.byType(DeletablePostCard));
    await tester.pumpAndSettle();
    expect(find.text('Delete'), findsNothing);
    expect(find.text('Report'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
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

  group("reporting somebody else's post", () {
    testWidgets('Report asks why, then thanks and waits to be dismissed', (
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
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(find.text('Report post'), findsOneWidget);
      expect(find.text('Hate or harassment'), findsOneWidget);
      await tester.tap(find.text('Hate or harassment'));
      await tester.pumpAndSettle();

      expect(reports.sent, ['post|p1|not-me|hate']);
      expect(reports.hidden, ['post__p1']);
      // The card itself goes when the hidden set arrives, which no test
      // can stream in here; until then the overlay carries the promise.
      expect(find.text(kReportThanks), findsOneWidget);
      expect(find.text('Report'), findsNothing);
    });

    testWidgets('a report that fails says so, and hides nothing', (
      tester,
    ) async {
      final reports = _Reports(sends: false);
      await _pump(
        tester,
        viewerUid: 'me',
        post: _post(authorUid: 'not-me'),
        reports: reports,
      );
      await tester.longPress(find.byType(DeletablePostCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spam'));
      await tester.pumpAndSettle();

      expect(reports.hidden, isEmpty);
      expect(find.text(kReportFailed), findsOneWidget);
      // Still offered, so it can be tried again.
      expect(find.text('Report'), findsOneWidget);
    });

    testWidgets('Cancel leaves the card exactly as it was', (tester) async {
      final reports = _Reports();
      await _pump(
        tester,
        viewerUid: 'me',
        post: _post(authorUid: 'not-me'),
        reports: reports,
      );
      await tester.longPress(find.byType(DeletablePostCard));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(reports.sent, isEmpty);
      expect(reports.hidden, isEmpty);
      expect(find.text('Report'), findsOneWidget);
      expect(find.text(kReportThanks), findsNothing);
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

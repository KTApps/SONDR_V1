import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/single_post_screen.dart';
import 'package:sondr/features/feed/widgets/milestone_card.dart';
import 'package:sondr/features/feed/widgets/milestone_frame.dart';
import 'package:sondr/features/feed/widgets/mini_ring.dart';
import 'package:sondr/features/feed/widgets/session_card.dart';
import 'package:sondr/shared/cached_photo.dart';

import 'tiny_png.dart';

/// The session card: the milestone's frame, one photo, the band ring.
void main() {
  const cass = PostAuthor(username: 'cass', displayName: 'Cass');
  final now = DateTime.now();

  SessionPost post({
    List<PostPhoto> photos = const [PostPhoto(url: 'https://x/a.jpg', storagePath: 'a')],
    int? bandSeconds = 36000,
    String? caption = 'Done for today.',
  }) => SessionPost(
    id: 's1',
    authorUid: 'cass-uid',
    author: cass,
    createdAt: now.subtract(const Duration(hours: 5)),
    caption: caption,
    photos: photos,
    taskName: 'Spanish',
    sessionSeconds: 4800,
    bandSeconds: bandSeconds,
  );

  MilestonePost milestone() => MilestonePost(
    id: 'm1',
    authorUid: 'cass-uid',
    author: cass,
    createdAt: now.subtract(const Duration(hours: 5)),
    caption: 'Done for today.',
    photos: const [PostPhoto(url: 'https://x/a.jpg', storagePath: 'a')],
    taskName: 'Spanish',
    milestoneHours: 20,
    totalHours: 20,
  );

  late ImageProvider Function(String) before;
  setUp(() {
    before = photoImageProviderFactory;
    photoImageProviderFactory = (_) => MemoryImage(tinyPng);
  });
  tearDown(() => photoImageProviderFactory = before);

  Future<void> pump(WidgetTester tester, Widget card, {String uid = 'me'}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [currentUidProvider.overrideWithValue(uid)],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [card]),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder frame() => find.byType(AspectRatio).first;
  Finder scrim() => find.byWidgetPredicate(
    (w) => w is DecoratedBox && (w.decoration as BoxDecoration).gradient == kMilestoneScrim,
  );

  testWidgets('the milestone\'s frame and chrome: the same places, the same words', (tester) async {
    await pump(tester, MilestoneCard(post: milestone()));
    final mFrame = tester.getRect(frame());
    final mHandle = tester.getRect(find.text('cass'));
    final mTime = tester.getRect(find.text('5h'));
    final mLike = tester.getRect(find.text('Like'));
    final mCaption = tester.getRect(find.text('Done for today.'));

    await pump(tester, SessionCard(post: post()));
    expect(tester.getRect(frame()), mFrame);
    expect(tester.getRect(find.text('cass')), mHandle);
    expect(tester.getRect(find.text('5h')), mTime);
    expect(tester.getRect(find.text('Like')), mLike);
    expect(tester.getRect(find.text('Done for today.')), mCaption);
    expect(scrim(), findsOneWidget);
    expect(find.text('Spanish · 1h 20m'), findsOneWidget);
    expect(find.text('Comments'), findsOneWidget);
    expect(find.byType(PageView), findsNothing);
  });

  testWidgets('the small ring at the right, on the words\' line: grey to before this session, white for it', (tester) async {
    await pump(tester, SessionCard(post: post(bandSeconds: 36000)));
    final ring = find.byType(MiniRing);
    expect(ring, findsOneWidget);
    // Stored: 36000 into the band after this 4800 session.
    final data = tester.widget<MiniRing>(ring).data;
    expect(data, const MiniRingData(before: 36000 - 4800, seconds: 4800));
    expect(data.beforeFill, closeTo((36000 - 4800) / 72000, 1e-9));
    expect(data.ownFill, closeTo(0.5, 1e-9));
    final r = tester.getRect(ring);
    final fr = tester.getRect(frame());
    final like = tester.getRect(find.text('Like'));
    expect(r.width, 26);
    expect(fr.right - r.right, closeTo(18, 0.5));
    // On the words' baseline: the ring's bottom sits within the words' line.
    expect(r.bottom, lessThanOrEqualTo(like.bottom));
    expect(r.bottom, greaterThanOrEqualTo(like.top));
    // A session that crossed into a fresh band: nothing before it; a
    // figure beyond the band is clamped.
    expect(sessionRing(post(bandSeconds: 600))!.before, 0);
    expect(sessionRing(post(bandSeconds: 90000))!.ownFill, 1.0);
    expect(sessionRing(post(bandSeconds: null)), isNull);
  });

  testWidgets('a post from before, without the figure, has no ring', (tester) async {
    await pump(tester, SessionCard(post: post(bandSeconds: null)));
    expect(find.byType(MiniRing), findsNothing);
    expect(find.text('Spanish · 1h 20m'), findsOneWidget);
  });

  testWidgets('no photo: the surface, no scrim, the same text', (tester) async {
    await pump(tester, SessionCard(post: post(photos: const [], bandSeconds: null)));
    expect(find.byType(Image), findsNothing);
    expect(scrim(), findsNothing);
    expect(find.text('Spanish · 1h 20m'), findsOneWidget);
    expect(find.text('Done for today.'), findsOneWidget);
    expect(tester.getRect(frame()).width / tester.getRect(frame()).height, closeTo(3 / 4, 0.001));
  });

  testWidgets('a tap on the card goes nowhere', (tester) async {
    await pump(tester, SessionCard(post: post()));
    final r = tester.getRect(frame());
    for (final f in [0.1, 0.5, 0.9]) {
      await tester.tapAt(Offset(r.left + r.width * f, r.center.dy));
      await tester.pumpAndSettle();
    }
    expect(find.byType(SinglePostScreen), findsNothing);
    expect(find.byType(SessionCard), findsOneWidget);
  });

  testWidgets('the caption opens in place when tapped, and folds back', (tester) async {
    const long = 'Done for today. A long one that runs past the two lines the card '
        'gives it, and on, and on, so that there is something to open up.';
    await pump(tester, SessionCard(post: post(caption: long)));
    Text caption() => tester.widget<Text>(find.text(long));
    expect(caption().maxLines, 2);
    final folded = tester.getRect(find.text(long));
    final taskBefore = tester.getRect(find.text('Spanish · 1h 20m')).top;
    await tester.tap(find.text(long));
    await tester.pumpAndSettle();
    expect(caption().maxLines, isNull);
    expect(tester.getRect(find.text(long)).height, greaterThan(folded.height));
    // In place: the block grows upward over the photo; the frame is as it was.
    expect(tester.getRect(find.text('Spanish · 1h 20m')).top, lessThan(taskBefore));
    expect(tester.getRect(frame()).height, closeTo((390 - 32) * 4 / 3, 0.5));
    await tester.tap(find.text(long));
    await tester.pumpAndSettle();
    expect(caption().maxLines, 2);
  });

  testWidgets('the author sees Likes', (tester) async {
    await pump(tester, SessionCard(post: post()), uid: 'cass-uid');
    expect(find.text('Likes'), findsOneWidget);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/band_story.dart';
import 'package:sondr/features/feed/milestone_hints.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/single_post_screen.dart';
import 'package:sondr/features/feed/widgets/deletable_post_card.dart';
import 'package:sondr/features/feed/widgets/milestone_card.dart';
import 'package:sondr/features/feed/widgets/milestone_cover.dart';
import 'package:sondr/features/feed/widgets/milestone_frame.dart';
import 'package:sondr/features/feed/widgets/milestone_ring.dart';
import 'package:sondr/features/feed/widgets/mini_ring.dart';
import 'package:sondr/features/feed/widgets/post_chrome.dart' show kTextShadows;
import 'package:sondr/shared/cached_photo.dart';

import 'tiny_png.dart';

/// The milestone card: one frame, the cover, the pages a tap steps through.
void main() {
  const cass = PostAuthor(username: 'cass', displayName: 'Cass');
  final now = DateTime.now();

  final sessions = [
    PostSegment(at: DateTime(2026, 10, 6, 9).millisecondsSinceEpoch, seconds: 7200, photo: true),
    PostSegment(at: DateTime(2026, 10, 7, 18).millisecondsSinceEpoch, seconds: 2400),
    PostSegment(at: DateTime(2026, 10, 9, 7).millisecondsSinceEpoch, seconds: 4800, photo: true),
  ];

  PostPhoto photo(String id, {int? session}) =>
      PostPhoto(url: 'https://x/$id.jpg', storagePath: id, sessionIndex: session);

  MilestonePost post({
    required List<PostPhoto> photos,
    bool story = true,
    String? caption = 'Twenty hours in. Starting to dream in it.',
    String authorUid = 'cass-uid',
    String? coverUrl,
    String id = 'm1',
  }) => MilestonePost(
    id: id,
    authorUid: authorUid,
    author: cass,
    createdAt: now.subtract(const Duration(hours: 5)),
    caption: caption,
    photos: photos,
    taskName: 'Spanish',
    milestoneHours: 20,
    totalHours: 20,
    segments: story ? sessions : const [],
    unit: story ? SegmentUnit.session : null,
    coverUrl: coverUrl,
  );

  // Stored oldest first, as the share writes them.
  MilestonePost twoPhotos({String? coverUrl, String id = 'm1'}) => post(
    photos: [photo('early', session: 0), photo('crossing', session: 2)],
    coverUrl: coverUrl,
    id: id,
  );

  late ImageProvider Function(String) factoryBefore;
  setUp(() {
    factoryBefore = photoImageProviderFactory;
    photoImageProviderFactory = (_) => MemoryImage(tinyPng);
  });
  tearDown(() => photoImageProviderFactory = factoryBefore);

  /// The card in a feed-shaped list: the gutter, and room to scroll.
  Future<void> pump(
    WidgetTester tester,
    MilestonePost p, {
    String uid = 'me',
    bool deletable = false,
    MilestoneHints? hints,
  }) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final card = MilestoneCard(post: p);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue(uid),
          milestoneHintsProvider.overrideWithValue(
            hints ?? MemoryMilestoneHints(const MilestoneHintState(tapped: true)),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                deletable ? DeletablePostCard(post: p, child: card) : card,
                const SizedBox(height: 1200),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder frame() => find.byType(AspectRatio).first;

  Finder dots() => find.byWidgetPredicate(
    (w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).shape == BoxShape.circle,
  );

  Finder scrim() => find.byWidgetPredicate(
    (w) => w is DecoratedBox && (w.decoration as BoxDecoration).gradient == kMilestoneScrim,
  );

  Future<void> tapAt(WidgetTester tester, double fraction) async {
    final r = tester.getRect(frame());
    await tester.tapAt(Offset(r.left + r.width * fraction, r.center.dy));
    await tester.pumpAndSettle();
  }

  group('the frame', () {
    testWidgets('is 3:4 at the feed\'s card width; the cover is drawn when there is none stored', (tester) async {
      await pump(tester, twoPhotos());
      final r = tester.getRect(frame());
      expect(r.width, 390 - 32);
      expect(r.width / r.height, closeTo(3 / 4, 0.001));
      expect(find.byType(MilestoneCover), findsOneWidget);
      expect(find.byType(MilestoneCollage), findsOneWidget);
      expect(find.byType(MilestoneRing), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
    });

    testWidgets('a stored cover is shown as one image, with no ring drawn over it', (tester) async {
      await pump(tester, twoPhotos(coverUrl: 'https://x/cover.jpg'));
      expect(find.byType(MilestoneCover), findsNothing);
      expect(find.byType(MilestoneRing), findsNothing);
      expect(scrim(), findsNothing);
      expect(find.byType(Image), findsOneWidget);
      // The chrome is still the card's.
      expect(find.text('cass'), findsOneWidget);
      expect(find.text('Spanish'), findsOneWidget);
    });

    testWidgets('with no photo it is the surface and the ring, no scrim', (tester) async {
      await pump(tester, post(photos: const []));
      expect(find.byType(MilestoneNoPhotoFrame), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(scrim(), findsNothing);
      expect(find.byType(MiniRing), findsNothing);
      expect(find.text('20'), findsOneWidget);
      expect(tester.widget<MilestoneRing>(find.byType(MilestoneRing)).onPhoto, isFalse);
    });

    testWidgets('the handle left and the time right above; task, caption, actions below', (tester) async {
      await pump(tester, twoPhotos());
      final r = tester.getRect(frame());
      final handle = tester.getRect(find.text('cass'));
      expect(handle.top - r.top, closeTo(16, 0.5));
      expect(handle.left - r.left, closeTo(18, 0.5));
      final time = tester.getRect(find.text('5h'));
      expect(r.right - time.right, closeTo(18, 0.5));
      expect(find.text('Spanish'), findsOneWidget);
      expect(find.text('Twenty hours in. Starting to dream in it.'), findsOneWidget);
      // Actions at the left: Like starts at the inset, 16 from the bottom.
      final like = tester.getRect(find.text('Like'));
      expect(like.left - r.left, closeTo(18, 0.5));
      expect(r.bottom - like.bottom, closeTo(16, 0.5));
      // No dots, and no ring on the cover.
      expect(dots(), findsNothing);
      expect(find.byType(MiniRing), findsNothing);
      // Every word over the photo wears the one soft shadow.
      for (final t in ['cass', '5h', 'Spanish', 'Twenty hours in. Starting to dream in it.', 'Like', 'Comments']) {
        expect(tester.widget<Text>(find.text(t)).style?.shadows, kTextShadows, reason: t);
      }
    });

    testWidgets('the author sees Likes', (tester) async {
      await pump(tester, twoPhotos(), uid: 'cass-uid');
      expect(find.text('Likes'), findsOneWidget);
    });
  });

  group('the ring\'s text', () {
    /// The figure and the unit on the page, as drawn.
    (Text figure, Text unit) ringText(WidgetTester tester) {
      final centre = find.byType(MilestoneRingCentre);
      final texts = tester.widgetList<Text>(find.descendant(of: centre, matching: find.byType(Text))).toList();
      return (texts[0], texts[1]);
    }

    testWidgets('is the hours over the word on the cover, at one size, with the shadow; a photo page has no ring text', (tester) async {
      await pump(tester, twoPhotos());
      final (coverFigure, coverUnit) = ringText(tester);
      expect(coverFigure.data, '20');
      expect(coverUnit.data, 'hours');
      expect(coverFigure.style?.fontSize, kMilestoneFigureSize);
      expect(coverFigure.style?.shadows, kTextShadows);
      expect(coverUnit.style?.shadows, kTextShadows);
      expect(
        find.descendant(of: find.byType(MilestoneRingCentre), matching: find.byType(FittedBox)),
        findsNothing,
        reason: 'nothing is fitted per page',
      );
      await tapAt(tester, 0.9);
      expect(find.byType(MilestoneRingCentre), findsNothing);
    });

    testWidgets('"12h 59m" fits inside the ring at that size, with margin', (tester) async {
      await pump(tester, twoPhotos());
      final context = tester.element(find.byType(MilestoneRingCentre));
      final painter = TextPainter(
        text: TextSpan(text: '12h 59m', style: MilestoneRingCentre.figureStyle(context, onPhoto: true)),
        textDirection: TextDirection.ltr,
      )..layout();
      final allowed = MilestoneRingCentre.widthFor(kMilestoneRingSize, onPhoto: true);
      expect(painter.width, lessThan(allowed));
      expect(painter.width, lessThan(const MilestoneRingGeometry(onPhoto: true).inner - 24));
    });
  });

  group('stepping through', () {
    testWidgets('no dots, whatever the count', (tester) async {
      await pump(tester, twoPhotos());
      expect(dots(), findsNothing);
      await pump(tester, post(photos: [photo('only', session: 2)]));
      expect(dots(), findsNothing);
    });

    testWidgets('the right third steps to each photo — the task line with its session, the small ring, no big ring, no date — and from the last round to the cover; the left steps back and the cover stays', (tester) async {
      await pump(tester, twoPhotos());
      expect(find.text('20'), findsOneWidget);
      await tapAt(tester, 0.9);
      // Photo 1: the early one, session 0 — 2h, nothing before it.
      expect(find.text('Spanish · 2h'), findsOneWidget);
      expect(find.byType(MilestoneRing), findsNothing);
      expect(find.text('20'), findsNothing);
      expect(find.text('6 Oct'), findsNothing);
      expect(find.byType(MilestoneCover), findsNothing);
      expect(scrim(), findsOneWidget);
      var ring = tester.widget<MiniRing>(find.byType(MiniRing));
      expect(ring.data, const MiniRingData(before: 0, seconds: 7200));
      final r = tester.getRect(frame());
      final like = tester.getRect(find.text('Like'));
      final mini = tester.getRect(find.byType(MiniRing));
      expect(r.right - mini.right, closeTo(18, 0.5));
      expect(mini.bottom, lessThanOrEqualTo(like.bottom));
      expect(mini.bottom, greaterThanOrEqualTo(like.top));
      await tapAt(tester, 0.9);
      // Photo 2: the crossing, session 2 — 1h 20m, after 2h and 40m.
      expect(find.text('Spanish · 1h 20m'), findsOneWidget);
      ring = tester.widget<MiniRing>(find.byType(MiniRing));
      expect(ring.data, const MiniRingData(before: 7200 + 2400, seconds: 4800));
      // The last page: the right goes round to the cover.
      await tapAt(tester, 0.9);
      expect(find.text('20'), findsOneWidget);
      expect(find.text('Spanish'), findsOneWidget);
      expect(find.byType(MiniRing), findsNothing);
      // The left on the cover stays put.
      await tapAt(tester, 0.1);
      expect(find.text('20'), findsOneWidget);
      // On, then back.
      await tapAt(tester, 0.9);
      await tapAt(tester, 0.9);
      expect(find.text('Spanish · 1h 20m'), findsOneWidget);
      await tapAt(tester, 0.1);
      expect(find.text('Spanish · 2h'), findsOneWidget);
      await tapAt(tester, 0.1);
      expect(find.text('20'), findsOneWidget);
      expect(find.byType(MilestoneCover), findsOneWidget);
      expect(find.byType(SinglePostScreen), findsNothing);
    });

    testWidgets('an old post pages through its photos with the task alone and no ring', (tester) async {
      await pump(tester, post(photos: [photo('a'), photo('b'), photo('c')], story: false));
      expect(dots(), findsNothing);
      await tapAt(tester, 0.9);
      expect(find.text('Spanish'), findsOneWidget);
      expect(find.text('20'), findsNothing);
      expect(find.text('hours'), findsNothing);
      expect(find.byType(MiniRing), findsNothing);
      expect(find.byType(MilestoneRing), findsNothing);
    });

    testWidgets('a vertical drag scrolls the feed', (tester) async {
      await pump(tester, twoPhotos());
      final before = tester.getRect(frame()).top;
      await tester.drag(frame(), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.getRect(frame()).top, lessThan(before - 100));
      expect(find.text('20'), findsOneWidget, reason: 'still on the cover');
    });
  });

  group('taps', () {
    testWidgets('the middle does nothing: no page, nowhere else', (tester) async {
      await pump(tester, twoPhotos());
      await tapAt(tester, 0.5);
      expect(find.byType(SinglePostScreen), findsNothing);
      expect(find.text('20'), findsOneWidget, reason: 'still the cover');
      // On a photo page the middle keeps the page; the thirds still step.
      await tapAt(tester, 0.9);
      expect(find.text('Spanish · 2h'), findsOneWidget);
      await tapAt(tester, 0.5);
      expect(find.text('Spanish · 2h'), findsOneWidget);
      expect(find.byType(SinglePostScreen), findsNothing);
    });

    testWidgets('with one photo a tap anywhere does nothing', (tester) async {
      await pump(tester, post(photos: [photo('only', session: 2)]));
      for (final f in [0.1, 0.5, 0.9]) {
        await tapAt(tester, f);
      }
      expect(find.byType(SinglePostScreen), findsNothing);
      expect(find.text('20'), findsOneWidget);
    });

    testWidgets('the caption opens in place when tapped, and folds back', (tester) async {
      const long = 'Twenty hours in. Starting to dream in it, and in the dreams everyone '
          'is patient with me, which is more than can be said for the waking ones.';
      await pump(tester, post(photos: [photo('only', session: 2)], caption: long));
      Text caption() => tester.widget<Text>(find.text(long));
      expect(caption().maxLines, 2);
      final folded = tester.getRect(find.text(long));
      final frameBefore = tester.getRect(frame());
      await tester.tap(find.text(long));
      await tester.pumpAndSettle();
      expect(caption().maxLines, isNull);
      expect(tester.getRect(find.text(long)).height, greaterThan(folded.height));
      expect(tester.getRect(frame()), frameBefore, reason: 'in place: the frame does not move');
      await tester.tap(find.text(long));
      await tester.pumpAndSettle();
      expect(caption().maxLines, 2);
    });

    testWidgets('a long press still asks to delete your own post', (tester) async {
      await pump(tester, twoPhotos(), uid: 'cass-uid', deletable: true);
      await tester.longPress(frame());
      await tester.pumpAndSettle();
      expect(find.text('Delete this post?'), findsOneWidget);
    });
  });

  group('the hint', () {
    testWidgets('on a fresh install the caption line says what to do, and the right third glows', (tester) async {
      final hints = MemoryMilestoneHints();
      await pump(tester, twoPhotos(), hints: hints);
      expect(find.text(kMilestoneHintText), findsOneWidget);
      expect(find.text('Twenty hours in. Starting to dream in it.'), findsNothing);
      // Shown: counted.
      await tester.pump();
      expect((await hints.read()).seen, ['m1']);
      // The glow animates and ends.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
    });

    testWidgets('a single photo gets no hint', (tester) async {
      await pump(tester, post(photos: [photo('only')]), hints: MemoryMilestoneHints());
      expect(find.text(kMilestoneHintText), findsNothing);
    });

    testWidgets('tapping the right side ends the hint for good', (tester) async {
      final hints = MemoryMilestoneHints();
      await pump(tester, twoPhotos(), hints: hints);
      await tapAt(tester, 0.9);
      expect((await hints.read()).tapped, isTrue);
      await tapAt(tester, 0.1);
      await tester.pumpAndSettle();
      expect(find.text(kMilestoneHintText), findsNothing);
      expect(find.text('Twenty hours in. Starting to dream in it.'), findsOneWidget);
    });

    testWidgets('a fourth post gets none', (tester) async {
      final hints = MemoryMilestoneHints(const MilestoneHintState(seen: ['a', 'b', 'c']));
      await pump(tester, twoPhotos(id: 'd'), hints: hints);
      expect(find.text(kMilestoneHintText), findsNothing);
    });
  });
}

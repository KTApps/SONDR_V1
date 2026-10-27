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

    testWidgets('with no photo it is the surface and the ring, no scrim, no dots', (tester) async {
      await pump(tester, post(photos: const []));
      expect(find.byType(MilestoneNoPhotoFrame), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(scrim(), findsNothing);
      expect(dots(), findsNothing);
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
      // Dots at the right, on the same line.
      final last = tester.getRect(dots().last);
      expect(r.right - last.right, closeTo(18, 0.5));
      expect(last.bottom, lessThanOrEqualTo(like.bottom));
      expect(last.top, greaterThanOrEqualTo(like.top));
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

    testWidgets('is one size on the cover and on every photo page', (tester) async {
      await pump(tester, twoPhotos());
      final (coverFigure, coverUnit) = ringText(tester);
      expect(coverFigure.data, '20');
      expect(coverFigure.style?.fontSize, kMilestoneFigureSize);
      expect(
        find.descendant(of: find.byType(MilestoneRingCentre), matching: find.byType(FittedBox)),
        findsNothing,
        reason: 'nothing is fitted per page',
      );
      await tapAt(tester, 0.9);
      final (pageFigure, pageUnit) = ringText(tester);
      expect(pageFigure.data, '2h');
      expect(pageFigure.style?.fontSize, coverFigure.style?.fontSize);
      expect(pageFigure.style?.fontWeight, coverFigure.style?.fontWeight);
      expect(pageUnit.style?.fontSize, coverUnit.style?.fontSize);
      expect(pageUnit.style?.fontWeight, coverUnit.style?.fontWeight);
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
    testWidgets('a dot per page: the cover and each photo; one photo has none', (tester) async {
      await pump(tester, twoPhotos());
      expect(dots(), findsNWidgets(3));
      await pump(tester, post(photos: [photo('only', session: 2)]));
      expect(dots(), findsNothing);
    });

    testWidgets('the right third steps to each photo, with its session in the ring; the left steps back', (tester) async {
      await pump(tester, twoPhotos());
      expect(find.text('20'), findsOneWidget);
      await tapAt(tester, 0.9);
      // Photo 1: the early one, session 0 — 2h on 6 Oct.
      expect(find.text('2h'), findsOneWidget);
      expect(find.text('6 Oct'), findsOneWidget);
      expect(find.byType(MilestoneCover), findsNothing);
      expect(scrim(), findsOneWidget);
      await tapAt(tester, 0.9);
      expect(find.text('1h 20m'), findsOneWidget);
      expect(find.text('9 Oct'), findsOneWidget);
      // The last page: another tap on the right stays put.
      await tapAt(tester, 0.9);
      expect(find.text('1h 20m'), findsOneWidget);
      await tapAt(tester, 0.1);
      expect(find.text('2h'), findsOneWidget);
      await tapAt(tester, 0.1);
      expect(find.text('20'), findsOneWidget);
      expect(find.byType(MilestoneCover), findsOneWidget);
      expect(find.byType(SinglePostScreen), findsNothing);
    });

    testWidgets('an old post pages through its photos with the hours on each', (tester) async {
      await pump(tester, post(photos: [photo('a'), photo('b'), photo('c')], story: false));
      expect(dots(), findsNWidgets(4));
      await tapAt(tester, 0.9);
      expect(find.text('20'), findsOneWidget);
      expect(find.text('hours'), findsOneWidget);
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
    testWidgets('the middle opens the post on its own page, with the caption in full', (tester) async {
      await pump(tester, twoPhotos());
      await tapAt(tester, 0.5);
      expect(find.byType(SinglePostScreen), findsOneWidget);
      expect(find.text('Twenty hours in. Starting to dream in it.'), findsNWidgets(2));
      // There, the middle goes nowhere further; the right still steps.
      await tapAt(tester, 0.5);
      expect(find.byType(SinglePostScreen), findsOneWidget);
      await tapAt(tester, 0.9);
      expect(find.text('2h'), findsOneWidget);
    });

    testWidgets('with one photo the whole card opens the post', (tester) async {
      await pump(tester, post(photos: [photo('only', session: 2)]));
      await tapAt(tester, 0.9);
      expect(find.byType(SinglePostScreen), findsOneWidget);
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

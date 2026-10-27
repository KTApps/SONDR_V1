import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/collage_layout.dart';
import 'package:sondr/features/feed/widgets/milestone_cover.dart';
import 'package:sondr/features/feed/widgets/milestone_frame.dart';
import 'package:sondr/features/feed/widgets/milestone_ring.dart';
import 'package:sondr/shared/cached_photo.dart';

import 'tiny_png.dart';

/// The cover as drawn: the collage's tiles where the layout puts them, the
/// ring where the card's is, and the whole scaled to any box.
void main() {
  List<ImageProvider> photos(int n) => [for (var i = 0; i < n; i++) MemoryImage(tinyPng)];

  Future<void> pump(WidgetTester tester, Widget child, {Size box = const Size(300, 400)}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Center(child: SizedBox.fromSize(size: box, child: child)),
      ),
    );
    await tester.pump();
  }

  testWidgets('the collage places a tile per photo where the layout says', (tester) async {
    await pump(tester, MilestoneCollage(photos: photos(5), size: const Size(300, 400)));
    final tiles = find.byType(FramedPhoto);
    expect(tiles, findsNWidgets(5));
    final origin = tester.getTopLeft(find.byType(MilestoneCollage));
    final expected = collageTiles(const Size(300, 400), 5);
    for (var i = 0; i < 5; i++) {
      final r = tester.getRect(tiles.at(i)).shift(-origin);
      expect(r.left, closeTo(expected[i].left, 0.01), reason: 'tile $i');
      expect(r.top, closeTo(expected[i].top, 0.01), reason: 'tile $i');
      expect(r.width, closeTo(expected[i].width, 0.01), reason: 'tile $i');
      expect(r.height, closeTo(expected[i].height, 0.01), reason: 'tile $i');
    }
  });

  testWidgets('nine at most', (tester) async {
    await pump(tester, MilestoneCollage(photos: photos(12), size: const Size(300, 400)));
    expect(find.byType(FramedPhoto), findsNWidgets(9));
  });

  testWidgets('a framing zooms and nudges the photo in its tile', (tester) async {
    await pump(
      tester,
      MilestoneCollage(
        photos: photos(1),
        size: const Size(300, 400),
        framings: const [PhotoFraming(scale: 1.5, dx: 0.1, dy: -0.1)],
      ),
    );
    expect(find.byType(Transform), findsNWidgets(2));
    // The tile itself is unmoved: the photo moves inside it, clipped.
    final tile = tester.getRect(find.byType(FramedPhoto));
    expect(tile.size, const Size(300, 400));
    expect(find.byType(ClipRect), findsOneWidget);
  });

  testWidgets('the cover fills a thumbnail with the same picture, small', (tester) async {
    await pump(
      tester,
      MilestoneCover(photos: photos(3), milestoneHours: 40),
      box: const Size(72, 72),
    );
    expect(find.byType(FramedPhoto), findsNWidgets(3));
    expect(find.text('40'), findsOneWidget);
    // Drawn at the frame's reference size and scaled to cover the square.
    final fitted = tester.widget<FittedBox>(find.byType(FittedBox).first);
    expect(fitted.fit, BoxFit.cover);
    final composition = tester.getSize(find.byType(SizedBox).first);
    expect(composition, const Size(72, 72));
  });

  testWidgets('at the card\'s width the ring sits at 44%, the scrim over the tiles', (tester) async {
    await pump(
      tester,
      MilestoneCover(photos: photos(4), milestoneHours: 20),
      box: kMilestoneFrameSize,
    );
    final top = tester.getTopLeft(find.byType(MilestoneCover)).dy;
    final ring = tester.getRect(find.byType(MilestoneRing));
    expect(ring.width, closeTo(kMilestoneRingSize, 0.01));
    expect(ring.center.dy - top, closeTo(kMilestoneFrameSize.height * 0.44, 0.01));
    expect(
      find.byWidgetPredicate((w) => w is DecoratedBox && (w.decoration as BoxDecoration).gradient == kMilestoneScrim),
      findsOneWidget,
    );
  });

  testWidgets('the thumbnail is the collage alone — no ring, no scrim — drawn, or the rendered one', (tester) async {
    final before = photoImageProviderFactory;
    photoImageProviderFactory = (_) => MemoryImage(tinyPng);
    addTearDown(() => photoImageProviderFactory = before);
    await pump(
      tester,
      const MilestoneCollageThumb(photoUrls: ['https://x/a.jpg', 'https://x/b.jpg', 'https://x/c.jpg']),
      box: const Size(80, 80),
    );
    expect(find.byType(FramedPhoto), findsNWidgets(3));
    expect(find.byType(MilestoneRing), findsNothing);
    expect(find.text('hours'), findsNothing);
    expect(
      find.byWidgetPredicate((w) => w is DecoratedBox && (w.decoration as BoxDecoration).gradient == kMilestoneScrim),
      findsNothing,
    );
    await pump(
      tester,
      const MilestoneCollageThumb(photoUrls: ['https://x/a.jpg'], thumbUrl: 'https://x/thumb.jpg'),
      box: const Size(80, 80),
    );
    expect(find.byType(FramedPhoto), findsNothing);
    expect(tester.widget<SondrPhoto>(find.byType(SondrPhoto)).url, 'https://x/thumb.jpg');
  });
}

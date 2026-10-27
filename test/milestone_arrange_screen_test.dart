import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/widgets/milestone_cover.dart';
import 'package:sondr/features/feed/widgets/milestone_frame.dart';
import 'package:sondr/features/feed/widgets/milestone_ring.dart';
import 'package:sondr/features/photos/milestone_arrange_screen.dart';
import 'package:sondr/features/photos/milestone_arrangement.dart';
import 'package:sondr/features/photos/models/photo.dart';

import 'tiny_png.dart';

/// Arrange: one screen, the collage live, the band to choose from.
void main() {
  const w = 390.0, h = 844.0;

  Photo photo(int ts) => Photo(
    taskId: 't', taskName: 'Spanish', dayKey: '2026-10-01', timestamp: ts,
    sessionSeconds: 60, photoUrl: 'https://x/$ts.jpg', storagePath: 'p$ts',
  );
  List<ArrangeEntry> entries({int band = 3, bool shot = true}) => [
    for (var i = 1; i <= band; i++)
      ArrangeEntry(id: photo(i).id, image: MemoryImage(tinyPng), photo: photo(i)),
    if (shot) ArrangeEntry(id: ArrangeEntry.newShotId, image: MemoryImage(tinyPng), shot: tinyPng),
  ];

  /// Pushes the screen from a button, so its result can be read.
  Future<ArrangeOutcome?> Function() pushed = () async => null;
  Future<void> open(
    WidgetTester tester, {
    List<ArrangeEntry>? items,
    Arrangement? initial,
    double textScale = 1.0,
    double width = w,
    double height = h,
    Future<bool> Function(WidgetRef)? onKeep,
  }) async {
    tester.view.physicalSize = Size(width * 3, height * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    final result = <ArrangeOutcome?>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          // A fresh navigator each time: a second open must not land on
          // the route the first one pushed.
          key: UniqueKey(),
          theme: AppTheme.dark(),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result.add(await Navigator.of(context).push<ArrangeOutcome>(
                  MaterialPageRoute(
                    builder: (_) => MilestoneArrangeScreen(
                      entries: items ?? entries(),
                      milestoneHours: 20,
                      initial: initial,
                      onKeep: onKeep,
                    ),
                  ),
                ));
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    pushed = () async => result.isEmpty ? null : result.last;
  }

  Finder strip() => find.byKey(kArrangeStripKey);
  Finder stripTiles() => find.descendant(of: strip(), matching: find.byType(ClipRRect));
  Finder preview() => find.byKey(kArrangePreviewKey);
  Finder previewTiles() => find.descendant(of: preview(), matching: find.byType(FramedPhoto));
  Finder outline() => find.byKey(const Key('sondr-arrange-outline'));

  double opacityOf(WidgetTester tester, Finder tile) =>
      tester.widget<Opacity>(find.ancestor(of: tile, matching: find.byType(Opacity)).first).opacity;

  group('the screen', () {
    for (final ts in [0.824, 1.0, 1.235]) {
      testWidgets('fits without scrolling at textScale $ts', (tester) async {
        await open(tester, textScale: ts);
        expect(tester.takeException(), isNull);
        final next = tester.getRect(find.text('Next'));
        final help = tester.getRect(find.byKey(kArrangeHelpKey));
        expect(next.bottom, lessThanOrEqualTo(h - 34));
        expect(help.bottom, lessThan(next.top));
        expect(find.byType(Scrollable), findsOneWidget, reason: 'only the strip scrolls');
        // ignore: avoid_print
        print('ARRANGE ts=$ts help.bottom=${help.bottom.toStringAsFixed(1)} next.top=${next.top.toStringAsFixed(1)} next.bottom=${next.bottom.toStringAsFixed(1)} of $h');
      });
    }

    testWidgets('Keep left, Retake right — Retake only with a new photo', (tester) async {
      await open(tester);
      final keep = tester.getRect(find.text('Keep'));
      final retake = tester.getRect(find.text('Retake'));
      expect(keep.left, lessThan(w / 2));
      expect(retake.right, greaterThan(w / 2));
      expect(keep.top, greaterThan(47 + 12 - 0.5));
      await open(tester, items: entries(shot: false));
      expect(find.text('Retake'), findsNothing);
      expect(find.text('Keep'), findsOneWidget);
    });

    testWidgets('the preview is the card\'s frame with the ring and the scrim; the help line reads', (tester) async {
      await open(tester);
      final r = tester.getRect(preview());
      expect(r.width, w - 32);
      expect(r.width / r.height, closeTo(3 / 4, 0.001));
      expect(find.descendant(of: preview(), matching: find.byType(MilestoneRing)), findsOneWidget);
      expect(
        find.descendant(
          of: preview(),
          matching: find.byWidgetPredicate((x) => x is DecoratedBox && (x.decoration as BoxDecoration).gradient == kMilestoneScrim),
        ),
        findsOneWidget,
      );
      expect(find.text('20'), findsOneWidget);
      expect(find.text(kArrangeHelp), findsOneWidget);
      expect(find.text('cass'), findsNothing, reason: 'no handle, no actions on the preview');
      expect(find.text('Like'), findsNothing);
    });
  });

  group('choosing', () {
    testWidgets('the default is the new photo alone, numbered 1; the band dimmed', (tester) async {
      await open(tester);
      expect(previewTiles(), findsOneWidget);
      expect(stripTiles(), findsNWidgets(4));
      expect(find.descendant(of: strip(), matching: find.text('1')), findsOneWidget);
      expect(opacityOf(tester, stripTiles().at(0)), 0.3);
      expect(opacityOf(tester, stripTiles().at(3)), 1);
      // The strip starts at the left gutter.
      expect(tester.getRect(stripTiles().first).left, 16);
      expect(tester.getSize(stripTiles().first), const Size(46, 61));
      expect(tester.getRect(stripTiles().at(1)).left - tester.getRect(stripTiles().at(0)).right, 6);
    });

    testWidgets('with no new photo nothing is chosen: the no-photo frame', (tester) async {
      await open(tester, items: entries(shot: false));
      expect(find.byType(MilestoneNoPhotoFrame), findsOneWidget);
      expect(previewTiles(), findsNothing);
      expect(find.descendant(of: strip(), matching: find.text('1')), findsNothing);
    });

    testWidgets('a tap adds a photo at the next position; a tap again removes it', (tester) async {
      await open(tester);
      await tester.tap(stripTiles().at(0));
      await tester.pumpAndSettle();
      expect(previewTiles(), findsNWidgets(2));
      expect(find.descendant(of: strip(), matching: find.text('2')), findsOneWidget);
      expect(opacityOf(tester, stripTiles().at(0)), 1);
      await tester.tap(stripTiles().at(0));
      await tester.pumpAndSettle();
      expect(previewTiles(), findsOneWidget);
      expect(find.descendant(of: strip(), matching: find.text('2')), findsNothing);
    });

    testWidgets('a tenth does nothing, and the help line says so for a moment', (tester) async {
      // Wide and tall, so every strip tile is on screen to be tapped.
      await open(tester, items: entries(band: 10), width: 900, height: 1700);
      for (var i = 0; i < 8; i++) {
        await tester.tap(stripTiles().at(i));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(previewTiles(), findsNWidgets(9));
      await tester.tap(stripTiles().at(8));
      await tester.pump();
      expect(previewTiles(), findsNWidgets(9));
      expect(find.text(kArrangeFullHelp), findsOneWidget);
      expect(find.text(kArrangeHelp), findsNothing);
      await tester.pump(kArrangeFullHelpFor + const Duration(milliseconds: 50));
      expect(find.text(kArrangeHelp), findsOneWidget);
    });
  });

  group('the tiles', () {
    testWidgets('a tap selects a tile for framing; a tap elsewhere lets it go', (tester) async {
      await open(tester);
      await tester.tap(stripTiles().at(0));
      await tester.pumpAndSettle();
      expect(outline(), findsNothing);
      await tester.tap(previewTiles().at(0));
      await tester.pumpAndSettle();
      expect(outline(), findsOneWidget);
      // Elsewhere: the help line.
      await tester.tap(find.byKey(kArrangeHelpKey));
      await tester.pumpAndSettle();
      expect(outline(), findsNothing);
    });

    testWidgets('a long press picks a tile up and dropping it on another swaps them', (tester) async {
      await open(tester);
      await tester.tap(stripTiles().at(0));
      await tester.pumpAndSettle();
      // Order: new shot (1), band 1 (2). Top tile to bottom tile.
      final from = tester.getCenter(previewTiles().at(0));
      final to = tester.getCenter(previewTiles().at(1));
      final g = await tester.startGesture(from);
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await g.moveTo(to);
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      final out = await pushed();
      expect(out?.kind, ArrangeOutcomeKind.next);
      expect(out?.arrangement?.order, [photo(1).id, ArrangeEntry.newShotId]);
    });

    testWidgets('a pinch on the selected tile frames its photo, and the framing goes with Next', (tester) async {
      await open(tester);
      await tester.tap(previewTiles().at(0));
      await tester.pumpAndSettle();
      final c = tester.getCenter(previewTiles().at(0));
      final a = await tester.createGesture();
      final b = await tester.createGesture();
      await a.down(c - const Offset(20, 0));
      await b.down(c + const Offset(20, 0));
      await tester.pump();
      await a.moveTo(c - const Offset(50, 0));
      await b.moveTo(c + const Offset(50, 0));
      await tester.pump();
      await a.up();
      await b.up();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      final out = await pushed();
      final framing = out?.arrangement?.framingOf(ArrangeEntry.newShotId);
      expect(framing?.scale, greaterThan(1.2));
      expect(framing?.scale, lessThanOrEqualTo(3));
    });

    testWidgets('an unselected tile does not move under a finger', (tester) async {
      await open(tester);
      final c = tester.getCenter(previewTiles().at(0));
      await tester.dragFrom(c, const Offset(60, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      final out = await pushed();
      expect(out?.arrangement?.framings, isEmpty);
    });
  });

  group('the ways out', () {
    testWidgets('Keep asks first, and Back keeps the screen', (tester) async {
      var kept = 0;
      await open(tester, onKeep: (_) async {
        kept++;
        return true;
      });
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(find.text(kKeepTitle), findsOneWidget);
      expect(find.text(kKeepBody), findsOneWidget);
      await tester.tap(find.text('Back').hitTestable());
      await tester.pumpAndSettle();
      expect(find.text(kKeepTitle), findsNothing);
      expect(kept, 0);
      expect(find.byType(MilestoneArrangeScreen), findsOneWidget);
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep').hitTestable().last);
      await tester.pumpAndSettle();
      expect(kept, 1);
      expect((await pushed())?.kind, ArrangeOutcomeKind.kept);
    });

    testWidgets('Retake carries the arrangement back to the camera', (tester) async {
      await open(tester);
      await tester.tap(stripTiles().at(0));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Retake'));
      await tester.pumpAndSettle();
      final out = await pushed();
      expect(out?.kind, ArrangeOutcomeKind.retake);
      expect(out?.arrangement?.order, [ArrangeEntry.newShotId, photo(1).id]);
    });

    testWidgets('a previous arrangement is where things start', (tester) async {
      final initial = Arrangement(order: [photo(2).id, ArrangeEntry.newShotId]);
      await open(tester, initial: initial);
      expect(previewTiles(), findsNWidgets(2));
      expect(find.descendant(of: strip(), matching: find.text('1')), findsOneWidget);
      expect(find.descendant(of: strip(), matching: find.text('2')), findsOneWidget);
    });
  });
}

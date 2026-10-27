import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/band_story.dart';
import 'package:sondr/features/feed/collage_layout.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/widgets/milestone_cover.dart';
import 'package:sondr/features/photos/milestone_arrange_screen.dart';
import 'package:sondr/features/photos/milestone_arrangement.dart';
import 'package:sondr/features/photos/milestone_final_look_screen.dart';
import 'package:sondr/features/photos/models/photo.dart';

/// Renders of Arrange and the final look, for looking at rather than
/// asserting: whole-screen PNGs at the iPhone 13 Pro, in Inter. Opt in
/// with `SONDR_RENDERS=1 flutter test test/milestone_arrange_renders_test.dart`;
/// the files land in ~/Desktop/sondr-arrange/.
void main() {
  final enabled = Platform.environment['SONDR_RENDERS'] == '1';
  final outDir = Directory('${Platform.environment['HOME']}/Desktop/sondr-arrange');
  const w = 390.0, h = 844.0;
  const samples = ['assets/mock/sample1.jpg', 'assets/mock/sample2.jpg'];

  Photo photo(int i) => Photo(
    taskId: 't', taskName: 'Spanish', dayKey: '2026-10-0${1 + i % 9}', timestamp: 1000 + i,
    sessionSeconds: 3600, photoUrl: samples[i % 2], storagePath: 'p$i',
  );
  List<ArrangeEntry> entries({int band = 3, bool shot = true}) => [
    for (var i = 0; i < band; i++)
      ArrangeEntry(id: photo(i).id, image: AssetImage(samples[i % 2]), photo: photo(i)),
    if (shot) ArrangeEntry(id: ArrangeEntry.newShotId, image: AssetImage(samples[1]), shot: Uint8List(0)),
  ];

  final key = GlobalKey();

  Future<void> capture(WidgetTester tester, String name) async {
    final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final png = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    outDir.createSync(recursive: true);
    final file = File('${outDir.path}/$name.png')..writeAsBytesSync(png!);
    // ignore: avoid_print
    print('RENDER ${file.path} ${png.length} bytes');
    expect(file.existsSync(), isTrue);
  }

  Future<void> pumpScreen(WidgetTester tester, Widget screen, {double keyboard = 0}) async {
    tester.view.physicalSize = const Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3.0;
    // As the engine reports it: with the keyboard over the home indicator
    // the bottom padding is gone, the inset having swallowed it.
    tester.view.padding = FakeViewPadding(top: 47 * 3, bottom: keyboard > 0 ? 0 : 34 * 3);
    if (keyboard > 0) tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: Stack(
          textDirection: TextDirection.ltr,
          children: [
            ProviderScope(
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: AppTheme.dark(),
                home: Builder(
                  builder: (c) {
                    ctx = c;
                    return screen;
                  },
                ),
              ),
            ),
            // The keyboard, drawn where the inset says it is.
            if (keyboard > 0)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: keyboard,
                child: const ColoredBox(color: Color(0xFF2C2C2E)),
              ),
          ],
        ),
      ),
    );
    await tester.runAsync(() async {
      for (final s in samples) {
        await precacheImage(AssetImage(s), ctx);
      }
    });
    await tester.pump();
    await tester.pump();
  }

  Finder previewTiles() =>
      find.descendant(of: find.byKey(kArrangePreviewKey), matching: find.byType(FramedPhoto));

  testWidgets('render arrange-default', (tester) async {
    await pumpScreen(tester, MilestoneArrangeScreen(entries: entries(), milestoneHours: 20));
    await capture(tester, 'arrange-default');
  }, skip: !enabled);

  testWidgets('render arrange-tile-selected', (tester) async {
    await pumpScreen(
      tester,
      MilestoneArrangeScreen(
        entries: entries(),
        milestoneHours: 20,
        initial: Arrangement(
          order: [photo(0).id, ArrangeEntry.newShotId, photo(2).id],
          framings: {photo(0).id: const PhotoFraming(scale: 1.6, dx: 0.1)},
        ),
      ),
    );
    await tester.tap(previewTiles().at(0));
    await tester.pumpAndSettle();
    await capture(tester, 'arrange-tile-selected');
  }, skip: !enabled);

  testWidgets('render arrange-9-photos', (tester) async {
    final items = entries(band: 10);
    await pumpScreen(
      tester,
      MilestoneArrangeScreen(
        entries: items,
        milestoneHours: 40,
        initial: Arrangement(order: [for (final e in items.take(9)) e.id]),
      ),
    );
    await capture(tester, 'arrange-9-photos');
  }, skip: !enabled);

  testWidgets('render arrange-no-photo', (tester) async {
    await pumpScreen(tester, MilestoneArrangeScreen(entries: entries(shot: false), milestoneHours: 20));
    await capture(tester, 'arrange-no-photo');
  }, skip: !enabled);

  final sessions = [
    for (var i = 0; i < 3; i++)
      PostSegment(at: DateTime(2026, 10, 1 + i, 9).millisecondsSinceEpoch, seconds: 3600 + i * 900, photo: true),
  ];
  final previewPhotos = [
    for (var i = 0; i < 3; i++)
      PostPhoto(url: samples[i % 2], storagePath: '', sessionIndex: i),
  ];

  Widget finalLook() => MilestoneFinalLookScreen(
    photos: previewPhotos,
    milestoneHours: 20,
    taskName: 'Spanish',
    handle: 'cass',
    segments: sessions,
    unit: SegmentUnit.session,
  );

  testWidgets('render final-look', (tester) async {
    await pumpScreen(tester, finalLook());
    await tester.enterText(find.byKey(kFinalLookCaptionKey), 'Twenty hours in. Starting to dream in it.');
    await tester.pumpAndSettle();
    await capture(tester, 'final-look');
  }, skip: !enabled);

  testWidgets('render final-look-keyboard', (tester) async {
    await pumpScreen(tester, finalLook(), keyboard: 336);
    await tester.showKeyboard(find.byKey(kFinalLookCaptionKey));
    await tester.enterText(find.byKey(kFinalLookCaptionKey), 'Twenty hours in.');
    await tester.pumpAndSettle();
    await capture(tester, 'final-look-keyboard');
  }, skip: !enabled);
}

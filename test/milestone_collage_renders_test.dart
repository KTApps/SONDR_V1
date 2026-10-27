import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/features/feed/band_story.dart';
import 'package:sondr/features/feed/milestone_hints.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/widgets/milestone_card.dart';
import 'package:sondr/features/feed/widgets/milestone_cover.dart';
import 'package:sondr/features/profile/profile_metrics.dart';
import 'package:sondr/shared/cached_photo.dart';

/// Renders of the collage card, for looking at rather than asserting:
/// PNGs at the iPhone 13 Pro's width, in Inter. Opt in with
/// `SONDR_RENDERS=1 flutter test test/milestone_collage_renders_test.dart`;
/// the files land in ~/Desktop/sondr-collage/.
void main() {
  final enabled = Platform.environment['SONDR_RENDERS'] == '1';
  final outDir = Directory('${Platform.environment['HOME']}/Desktop/sondr-collage');

  const cass = PostAuthor(username: 'cass', displayName: 'Cass');
  final now = DateTime.now();
  final sessions = [
    for (var i = 0; i < 9; i++)
      PostSegment(
        at: DateTime(2026, 10, 1 + i, 9).millisecondsSinceEpoch,
        seconds: 3600 + i * 900,
        photo: true,
      ),
  ];
  const samples = ['assets/mock/sample1.jpg', 'assets/mock/sample2.jpg'];

  List<PostPhoto> photos(int n) => [
    for (var i = 0; i < n; i++)
      PostPhoto(url: samples[i % 2], storagePath: 'p$i', sessionIndex: i),
  ];

  MilestonePost post(int n, {bool story = true, String id = 'm'}) => MilestonePost(
    id: id,
    authorUid: 'cass-uid',
    author: cass,
    createdAt: now.subtract(const Duration(hours: 3)),
    caption: 'Twenty hours in. Starting to dream in it.',
    photos: photos(n),
    taskName: 'Spanish',
    milestoneHours: 20,
    totalHours: 20,
    segments: story ? sessions : const [],
    unit: story ? SegmentUnit.session : null,
  );

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

  Future<void> pumpApp(WidgetTester tester, Widget body, {MilestoneHints? hints}) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('me'),
          milestoneHintsProvider.overrideWithValue(
            hints ?? MemoryMilestoneHints(const MilestoneHintState(tapped: true)),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return body;
              },
            ),
          ),
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

  Widget card(MilestonePost p) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    children: [RepaintBoundary(key: key, child: MilestoneCard(post: p))],
  );

  Future<void> tapRight(WidgetTester tester) async {
    final r = tester.getRect(find.byType(AspectRatio).first);
    await tester.tapAt(Offset(r.left + r.width * 0.9, r.center.dy));
    await tester.pumpAndSettle();
    await tester.pump();
  }

  for (var n = 1; n <= 9; n++) {
    testWidgets('render cover-$n', (tester) async {
      await pumpApp(tester, card(post(n)));
      await capture(tester, 'cover-$n');
    }, skip: !enabled);
  }

  testWidgets('render photo-page', (tester) async {
    await pumpApp(tester, card(post(3)));
    await tapRight(tester);
    await capture(tester, 'photo-page');
  }, skip: !enabled);

  testWidgets('render no-photo', (tester) async {
    await pumpApp(tester, card(post(0)));
    await capture(tester, 'no-photo');
  }, skip: !enabled);

  testWidgets('render hint', (tester) async {
    await pumpApp(tester, card(post(4)), hints: MemoryMilestoneHints());
    // Mid-glow.
    await tester.pump(const Duration(milliseconds: 700));
    await capture(tester, 'hint');
  }, skip: !enabled);

  testWidgets('render old-post', (tester) async {
    await pumpApp(tester, card(post(4, story: false)));
    await capture(tester, 'old-post');
  }, skip: !enabled);

  testWidgets('render profile-strip', (tester) async {
    // The tile loads its photos by URL; here the URLs are the bundled samples.
    final factoryBefore = photoImageProviderFactory;
    photoImageProviderFactory = (url) => AssetImage(url);
    addTearDown(() => photoImageProviderFactory = factoryBefore);
    final tokens = GreyscaleTokens.dark;
    await pumpApp(
      tester,
      ColoredBox(
        color: tokens.background,
        child: Center(
          child: RepaintBoundary(
            key: key,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    ProfileStripTile(
                      child: MilestoneCoverTile(
                        milestoneHours: 20 * (4 - i),
                        photoUrls: [for (final p in photos(2 + i * 2)) p.url],
                        saturation: kProfilePhotoSaturation,
                        tint: kProfilePhotoTint,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await capture(tester, 'profile-strip');
  }, skip: !enabled);
}

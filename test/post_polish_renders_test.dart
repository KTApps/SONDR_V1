import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/band_story.dart';
import 'package:sondr/features/feed/milestone_hints.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/widgets/milestone_card.dart';
import 'package:sondr/features/feed/widgets/session_card.dart';

/// Renders of the polished cards, for looking at rather than asserting:
/// PNGs at the iPhone 13 Pro's width, in Inter. Opt in with
/// `SONDR_RENDERS=1 flutter test test/post_polish_renders_test.dart`;
/// the files land in ~/Desktop/sondr-polish/.
void main() {
  final enabled = Platform.environment['SONDR_RENDERS'] == '1';
  final outDir = Directory('${Platform.environment['HOME']}/Desktop/sondr-polish');
  const dark = 'assets/mock/sample1.jpg';
  const bright = 'assets/mock/sample2.jpg';
  const cass = PostAuthor(username: 'cass', displayName: 'Cass');
  final now = DateTime.now();
  final sessions = [
    for (var i = 0; i < 4; i++)
      PostSegment(
        at: DateTime(2026, 10, 1 + i, 9).millisecondsSinceEpoch,
        seconds: 5400 + i * 1800,
        photo: true,
      ),
  ];

  MilestonePost milestone(String sample, {int n = 4}) => MilestonePost(
    id: 'm',
    authorUid: 'cass-uid',
    author: cass,
    createdAt: now.subtract(const Duration(hours: 3)),
    caption: 'Twenty hours in. Starting to dream in it.',
    photos: [for (var i = 0; i < n; i++) PostPhoto(url: sample, storagePath: 'p$i', sessionIndex: i)],
    taskName: 'Spanish',
    milestoneHours: 20,
    totalHours: 20,
    segments: sessions,
    unit: SegmentUnit.session,
  );

  SessionPost session(String sample) => SessionPost(
    id: 's',
    authorUid: 'cass-uid',
    author: cass,
    createdAt: now.subtract(const Duration(hours: 3)),
    caption: 'Done for today.',
    photos: [PostPhoto(url: sample, storagePath: '')],
    taskName: 'Guitar',
    sessionSeconds: 7200,
    bandSeconds: 36000,
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

  Future<void> pumpApp(WidgetTester tester, Widget card) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUidProvider.overrideWithValue('me'),
          milestoneHintsProvider.overrideWithValue(MemoryMilestoneHints(const MilestoneHintState(tapped: true))),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (c) {
                ctx = c;
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [RepaintBoundary(key: key, child: card)],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(() async {
      await precacheImage(const AssetImage(dark), ctx);
      await precacheImage(const AssetImage(bright), ctx);
    });
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapRight(WidgetTester tester) async {
    final r = tester.getRect(find.byType(AspectRatio).first);
    await tester.tapAt(Offset(r.left + r.width * 0.9, r.center.dy));
    await tester.pumpAndSettle();
    await tester.pump();
  }

  testWidgets('render milestone-cover-dark', (tester) async {
    await pumpApp(tester, MilestoneCard(post: milestone(dark)));
    await capture(tester, 'milestone-cover-dark');
  }, skip: !enabled);

  testWidgets('render milestone-cover-bright', (tester) async {
    await pumpApp(tester, MilestoneCard(post: milestone(bright)));
    await capture(tester, 'milestone-cover-bright');
  }, skip: !enabled);

  testWidgets('render milestone-photo-page', (tester) async {
    await pumpApp(tester, MilestoneCard(post: milestone(bright)));
    await tapRight(tester);
    await tapRight(tester);
    await capture(tester, 'milestone-photo-page');
  }, skip: !enabled);

  testWidgets('render session-post', (tester) async {
    await pumpApp(tester, SessionCard(post: session(dark)));
    await capture(tester, 'session-post');
  }, skip: !enabled);

  testWidgets('render session-post-bright', (tester) async {
    await pumpApp(tester, SessionCard(post: session(bright)));
    await capture(tester, 'session-post-bright');
  }, skip: !enabled);
}

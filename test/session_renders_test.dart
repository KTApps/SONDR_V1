import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/widgets/session_card.dart';
import 'package:sondr/features/photos/capture_review_screen.dart';
import 'package:sondr/features/photos/share_review_scaffold.dart';

/// Renders of the session card and its review, for looking at rather than
/// asserting. Opt in with `SONDR_RENDERS=1 flutter test test/session_renders_test.dart`;
/// the files land in ~/Desktop/sondr-session/.
void main() {
  final enabled = Platform.environment['SONDR_RENDERS'] == '1';
  final outDir = Directory('${Platform.environment['HOME']}/Desktop/sondr-session');
  const w = 390.0, h = 844.0;
  const sample = 'assets/mock/sample2.jpg';
  const cass = PostAuthor(username: 'cass', displayName: 'Cass');
  final now = DateTime.now();

  SessionPost post({int? bandSeconds}) => SessionPost(
    id: 's',
    authorUid: 'cass-uid',
    author: cass,
    createdAt: now.subtract(const Duration(hours: 3)),
    caption: 'Done for today.',
    photos: const [PostPhoto(url: sample, storagePath: '')],
    taskName: 'Spanish',
    sessionSeconds: 4800,
    bandSeconds: bandSeconds,
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

  Future<void> pumpApp(WidgetTester tester, Widget body, {double keyboard = 0, bool wholeScreen = false}) async {
    tester.view.physicalSize = const Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = FakeViewPadding(top: 47 * 3, bottom: keyboard > 0 ? 0 : 34 * 3);
    if (keyboard > 0) tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.reset);
    late BuildContext ctx;
    final app = ProviderScope(
      overrides: [currentUidProvider.overrideWithValue('me')],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
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
    );
    await tester.pumpWidget(
      wholeScreen
          ? RepaintBoundary(
              key: key,
              child: Stack(
                textDirection: TextDirection.ltr,
                children: [
                  app,
                  if (keyboard > 0)
                    Positioned(
                      left: 0, right: 0, bottom: 0, height: keyboard,
                      child: const ColoredBox(color: Color(0xFF2C2C2E)),
                    ),
                ],
              ),
            )
          : app,
    );
    await tester.runAsync(() => precacheImage(const AssetImage(sample), ctx));
    await tester.pump();
    await tester.pump();
  }

  Widget card(SessionPost p) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
    children: [RepaintBoundary(key: key, child: SessionCard(post: p))],
  );

  testWidgets('render feed-session', (tester) async {
    await pumpApp(tester, card(post(bandSeconds: 36000)));
    await capture(tester, 'feed-session');
  }, skip: !enabled);

  testWidgets('render feed-session-old', (tester) async {
    await pumpApp(tester, card(post()));
    await capture(tester, 'feed-session-old');
  }, skip: !enabled);

  Widget review({ShareState share = ShareState.allowed}) => CaptureReviewScreen(
    shotUrl: sample,
    taskName: 'Spanish',
    sessionSeconds: 4800,
    bandSeconds: 36000,
    handle: 'cass',
    share: share,
  );

  testWidgets('render review', (tester) async {
    await pumpApp(tester, review(), wholeScreen: true);
    await tester.enterText(find.byKey(kShareReviewCaptionKey), 'Done for today.');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await capture(tester, 'review');
  }, skip: !enabled);

  testWidgets('render review-keyboard', (tester) async {
    await pumpApp(tester, review(), wholeScreen: true, keyboard: 336);
    await tester.showKeyboard(find.byKey(kShareReviewCaptionKey));
    await tester.enterText(find.byKey(kShareReviewCaptionKey), 'Done for today.');
    await tester.pumpAndSettle();
    await capture(tester, 'review-keyboard');
  }, skip: !enabled);

  testWidgets('render review-locked', (tester) async {
    await pumpApp(tester, review(share: ShareState.underTwentyHours), wholeScreen: true);
    await capture(tester, 'review-locked');
  }, skip: !enabled);
}

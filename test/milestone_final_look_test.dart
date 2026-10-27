import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/band_story.dart';
import 'package:sondr/features/feed/collage_layout.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/widgets/comments_sheet.dart' show replyComposerClearance;
import 'package:sondr/features/feed/widgets/milestone_card.dart';
import 'package:sondr/shared/sondr_action.dart';
import 'package:sondr/features/photos/milestone_final_look_screen.dart';
import 'package:sondr/shared/cached_photo.dart';

import 'tiny_png.dart';

/// The final look: the card as friends will see it, the caption beneath.
void main() {
  const w = 390.0, h = 844.0;
  final sessions = [
    PostSegment(at: DateTime(2026, 10, 6, 9).millisecondsSinceEpoch, seconds: 7200, photo: true),
    PostSegment(at: DateTime(2026, 10, 9, 7).millisecondsSinceEpoch, seconds: 4800, photo: true),
  ];
  const photos = [
    PostPhoto(url: 'https://x/a.jpg', storagePath: '', sessionIndex: 0, framing: PhotoFraming(scale: 1.4)),
    PostPhoto(url: 'https://x/b.jpg', storagePath: '', sessionIndex: 1),
  ];

  setUp(() => photoImageProviderFactory = (_) => MemoryImage(tinyPng));

  Future<FinalLookOutcome?> Function() pushed = () async => null;
  Future<void> open(
    WidgetTester tester, {
    List<PostPhoto> items = photos,
    double keyboard = 0,
    double textScale = 1.0,
    Future<bool> Function(WidgetRef, String?)? onShare,
    Future<bool> Function(WidgetRef)? onKeep,
  }) async {
    tester.view.physicalSize = const Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3.0;
    // As the engine reports it: with the keyboard over the home indicator
    // the bottom padding is gone, the inset having swallowed it.
    tester.view.padding = FakeViewPadding(top: 47 * 3, bottom: keyboard > 0 ? 0 : 34 * 3);
    if (keyboard > 0) tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.reset);
    final result = <FinalLookOutcome?>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.dark(),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result.add(await Navigator.of(context).push<FinalLookOutcome>(
                  MaterialPageRoute(
                    builder: (_) => MilestoneFinalLookScreen(
                      photos: items,
                      milestoneHours: 20,
                      taskName: 'Spanish',
                      handle: 'cass',
                      segments: sessions,
                      unit: SegmentUnit.session,
                      onShare: onShare,
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

  Finder card() => find.byType(MilestoneCard);
  Finder inCard(String text) => find.descendant(of: card(), matching: find.text(text));

  testWidgets('the real card, as friends will see it: handle, now, task, dots, Like and Comments', (tester) async {
    await open(tester);
    expect(card(), findsOneWidget);
    final c = tester.widget<MilestoneCard>(card());
    expect(c.preview, isTrue);
    expect(c.opensPost, isFalse);
    expect(inCard('cass'), findsOneWidget);
    expect(inCard('now'), findsOneWidget);
    expect(inCard('Spanish'), findsOneWidget);
    expect(inCard('Like'), findsOneWidget);
    expect(inCard('Comments'), findsOneWidget);
    expect(inCard('20'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Keep'), findsOneWidget);
    // No explainer: the only lines are the card's, the field's and the actions'.
    expect(find.textContaining('friends'), findsNothing);
    // The card is the feed's width, at the gutter.
    expect(tester.getRect(card()).width, w - 32);
  });

  testWidgets('the thirds step through the pages with their sessions; Like does nothing', (tester) async {
    await open(tester);
    final r = tester.getRect(card());
    await tester.tapAt(Offset(r.left + r.width * 0.9, r.center.dy));
    await tester.pumpAndSettle();
    expect(inCard('2h'), findsOneWidget);
    expect(inCard('6 Oct'), findsOneWidget);
    await tester.tap(inCard('Like'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(inCard('Liked'), findsNothing);
    expect(find.byType(MilestoneFinalLookScreen), findsOneWidget);
  });

  testWidgets('the caption is a bare, centred field, and appears on the card as typed', (tester) async {
    await open(tester);
    final field = tester.widget<TextField>(find.byKey(kFinalLookCaptionKey));
    expect(field.decoration?.hintText, kCaptionHint);
    expect(field.decoration?.border, InputBorder.none);
    expect(field.decoration?.filled, isNot(true));
    expect(field.textAlign, TextAlign.center);
    expect(field.style?.fontSize, 14);
    expect(inCard('Twenty hours.'), findsNothing);
    await tester.enterText(find.byKey(kFinalLookCaptionKey), 'Twenty hours.');
    await tester.pumpAndSettle();
    expect(inCard('Twenty hours.'), findsOneWidget);
  });

  testWidgets('the caption stops at 200 characters', (tester) async {
    await open(tester);
    await tester.enterText(find.byKey(kFinalLookCaptionKey), 'x' * 250);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(find.byKey(kFinalLookCaptionKey)).controller?.text.length, 200);
  });

  group('with the keyboard up', () {
    Rect cursorBox(WidgetTester tester) => tester.getRect(
      find.descendant(of: find.byKey(kFinalLookCaptionKey), matching: find.byType(EditableText)),
    );

    testWidgets('Share and Keep go while typing, and come back after', (tester) async {
      await open(tester);
      final shareBefore = tester.getRect(find.text('Share'));
      final cardBefore = tester.getRect(card());
      // The keyboard comes up.
      tester.view.viewInsets = const FakeViewPadding(bottom: 336 * 3);
      tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 0);
      await tester.showKeyboard(find.byKey(kFinalLookCaptionKey));
      await tester.pumpAndSettle();
      expect(find.text('Share'), findsNothing);
      expect(find.text('Keep'), findsNothing);
      expect(find.byType(SondrAction), findsOneWidget, reason: 'only Back');
      // Return: the keyboard goes and the actions return, where they were.
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Keep'), findsOneWidget);
      tester.view.viewInsets = FakeViewPadding.zero;
      tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Share')), shareBefore);
      expect(tester.getRect(card()), cardBefore);
    });

    for (final ts in [0.824, 1.0, 1.235]) {
      testWidgets('at textScale $ts the field keeps the reply composer\'s clearance', (tester) async {
        await open(tester, keyboard: 336, textScale: ts);
        await tester.showKeyboard(find.byKey(kFinalLookCaptionKey));
        await tester.pumpAndSettle();
        final clearance = replyComposerClearance(tester.element(find.byKey(kFinalLookCaptionKey)));
        final below = (h - 336) - cursorBox(tester).bottom;
        // ignore: avoid_print
        print('FINAL-LOOK ts=$ts clearance=${clearance.toStringAsFixed(2)} below=${below.toStringAsFixed(2)}');
        expect(below, closeTo(clearance, 0.5));
      });
    }
  });

  testWidgets('Back goes back; Share posts with the caption; Keep keeps', (tester) async {
    await open(tester);
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect((await pushed())?.kind, FinalLookOutcomeKind.back);

    String? shared;
    await open(tester, onShare: (_, caption) async {
      shared = caption;
      return true;
    });
    await tester.enterText(find.byKey(kFinalLookCaptionKey), 'Done.');
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(shared, 'Done.');
    expect((await pushed())?.kind, FinalLookOutcomeKind.shared);

    var kept = 0;
    await open(tester, onKeep: (_) async {
      kept++;
      return true;
    });
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(kept, 1);
    expect((await pushed())?.kind, FinalLookOutcomeKind.kept);
  });

  testWidgets('a share that fails keeps the screen up and says so', (tester) async {
    await open(tester, onShare: (_, _) async => false);
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(find.byType(MilestoneFinalLookScreen), findsOneWidget);
    expect(find.textContaining('Couldn’t create the post'), findsOneWidget);
  });
}

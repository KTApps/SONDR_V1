import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/feed/models/post.dart';
import 'package:sondr/features/feed/widgets/comments_sheet.dart' show replyComposerClearance;
import 'package:sondr/features/feed/widgets/milestone_card.dart';
import 'package:sondr/features/feed/widgets/mini_ring.dart';
import 'package:sondr/features/feed/widgets/session_card.dart';
import 'package:sondr/features/photos/capture_review_screen.dart';
import 'package:sondr/features/photos/milestone_final_look_screen.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/share_review_scaffold.dart';
import 'package:sondr/shared/sondr_action.dart';

/// The session's review: its final look — the card as friends will see
/// it, the caption beneath, Share over Keep — laid out exactly as the
/// milestone's, and locked where sharing is not offered.
void main() {
  const w = 390.0, h = 844.0;

  Future<ReviewOutcome?> Function() pushed = () async => null;
  Future<void> open(
    WidgetTester tester, {
    ShareState share = ShareState.allowed,
    bool withShot = true,
    double keyboard = 0,
    Future<bool> Function(WidgetRef)? onKeep,
    Future<bool> Function(WidgetRef, String?)? onShare,
  }) async {
    tester.view.physicalSize = const Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = FakeViewPadding(top: 47 * 3, bottom: keyboard > 0 ? 0 : 34 * 3);
    if (keyboard > 0) tester.view.viewInsets = FakeViewPadding(bottom: keyboard * 3);
    addTearDown(tester.view.reset);
    final result = <ReviewOutcome?>[];
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result.add(await Navigator.of(context).push<ReviewOutcome>(
                  MaterialPageRoute(
                    builder: (_) => CaptureReviewScreen(
                      shotUrl: withShot ? 'assets/mock/sample1.jpg' : null,
                      taskName: 'Spanish',
                      sessionSeconds: 4800,
                      bandSeconds: 36000,
                      handle: 'cass',
                      share: share,
                      onKeep: onKeep,
                      onShare: onShare,
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

  /// The milestone's final look on the same viewport, for the positions
  /// the session's must match.
  Future<void> openFinalLook(WidgetTester tester) async {
    tester.view.physicalSize = const Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          key: UniqueKey(),
          theme: AppTheme.dark(),
          home: const MilestoneFinalLookScreen(
            photos: [PostPhoto(url: 'assets/mock/sample1.jpg', storagePath: '')],
            milestoneHours: 20,
            taskName: 'Spanish',
            handle: 'cass',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder card() => find.byType(SessionCard);
  Finder inCard(String text) => find.descendant(of: card(), matching: find.text(text));

  group('the card as friends will see it', () {
    testWidgets('the session card: handle, now, task and length, the ring; Retake top right', (tester) async {
      await open(tester);
      final c = tester.widget<SessionCard>(card());
      expect(c.preview, isTrue);
      expect(inCard('cass'), findsOneWidget);
      expect(inCard('now'), findsOneWidget);
      expect(inCard('Spanish · 1h 20m'), findsOneWidget);
      expect(inCard('Like'), findsOneWidget);
      expect(find.byType(MiniRing), findsOneWidget);
      expect(tester.widget<SessionCard>(card()).ring, const MiniRingData(before: 36000 - 4800, seconds: 4800));
      final retake = tester.getRect(find.text('Retake'));
      expect(retake.right, greaterThan(w / 2));
      expect(find.text('Back'), findsNothing);
      expect(tester.getRect(card()).width, w - 32);
    });

    testWidgets('the caption appears on the card as typed, bare and centred, 200 at most', (tester) async {
      await open(tester);
      final field = tester.widget<TextField>(find.byKey(kShareReviewCaptionKey));
      expect(field.decoration?.hintText, kCaptionHint);
      expect(field.decoration?.border, InputBorder.none);
      expect(field.textAlign, TextAlign.center);
      expect(field.style?.fontSize, 14);
      await tester.enterText(find.byKey(kShareReviewCaptionKey), 'Done for today.');
      await tester.pumpAndSettle();
      expect(inCard('Done for today.'), findsOneWidget);
      await tester.enterText(find.byKey(kShareReviewCaptionKey), 'x' * 250);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(kShareReviewCaptionKey)).controller?.text.length, 200);
    });
  });

  group('the layout matches the milestone\'s final look', () {
    testWidgets('card, field, Share and Keep sit where the final look puts them', (tester) async {
      await openFinalLook(tester);
      final cardFL = tester.getRect(find.byType(MilestoneCard));
      final fieldFL = tester.getRect(find.byKey(kShareReviewCaptionKey));
      final shareFL = tester.getRect(find.text('Share'));
      final keepFL = tester.getRect(find.text('Keep'));
      final topFL = tester.getRect(find.text('Back')).top;

      await open(tester);
      expect(tester.getRect(card()), cardFL);
      expect(tester.getRect(find.byKey(kShareReviewCaptionKey)), fieldFL);
      expect(tester.getRect(find.text('Share')), shareFL);
      expect(tester.getRect(find.text('Keep')), keepFL);
      expect(tester.getRect(find.text('Retake')).top, topFL);
    });

    testWidgets('with the keyboard up Share and Keep go and the field keeps the clearance', (tester) async {
      await open(tester, keyboard: 336);
      await tester.showKeyboard(find.byKey(kShareReviewCaptionKey));
      await tester.pumpAndSettle();
      expect(find.text('Share'), findsNothing);
      expect(find.text('Keep'), findsNothing);
      final cursor = tester.getRect(
        find.descendant(of: find.byKey(kShareReviewCaptionKey), matching: find.byType(EditableText)),
      );
      final clearance = replyComposerClearance(tester.element(find.byKey(kShareReviewCaptionKey)));
      expect((h - 336) - cursor.bottom, closeTo(clearance, 0.5));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Keep'), findsOneWidget);
    });
  });

  group('locked', () {
    testWidgets('under 20h: the reason where Share would be, Keep alone and white, no caption', (tester) async {
      await open(tester, share: ShareState.underTwentyHours);
      expect(find.text('Share'), findsNothing);
      expect(find.text('Sharing unlocks at 20h'), findsOneWidget);
      expect(find.byKey(kShareReviewCaptionKey), findsNothing);
      final keep = tester.widget<SondrAction>(find.widgetWithText(SondrAction, 'Keep'));
      expect(keep.supporting, isFalse);
      // Where Share sits: above Keep, centred.
      final reason = tester.getRect(find.text('Sharing unlocks at 20h'));
      final keepRect = tester.getRect(find.text('Keep'));
      expect(reason.bottom, lessThan(keepRect.top));
      expect(reason.center.dx, closeTo(w / 2, 1));
    });

    testWidgets('a guest is told what is missing, and it is not hours', (tester) async {
      await open(tester, share: ShareState.guest);
      expect(find.text('Create an account to share'), findsOneWidget);
      expect(find.text('Sharing unlocks at 20h'), findsNothing);
      expect(find.text('Share'), findsNothing);
      expect(find.text('Keep'), findsOneWidget);
    });

    testWidgets('a guest on the milestone\'s final look sees the same', (tester) async {
      tester.view.physicalSize = const Size(w * 3, h * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const MilestoneFinalLookScreen(
              photos: [PostPhoto(url: 'assets/mock/sample1.jpg', storagePath: '')],
              milestoneHours: 20,
              taskName: 'Spanish',
              handle: 'cass',
              share: ShareState.guest,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Create an account to share'), findsOneWidget);
      expect(find.text('Share'), findsNothing);
      expect(find.byKey(kShareReviewCaptionKey), findsNothing);
      expect(find.text('Keep'), findsOneWidget);
    });
  });

  group('the ways out', () {
    testWidgets('Retake goes back, and nothing is saved', (tester) async {
      var kept = 0;
      await open(tester, onKeep: (_) async {
        kept++;
        return true;
      });
      await tester.tap(find.text('Retake'));
      await tester.pumpAndSettle();
      expect((await pushed()), ReviewOutcome.retake);
      expect(kept, 0);
    });

    testWidgets('Keep saves and does not post; Share posts with the caption', (tester) async {
      var kept = 0;
      String? shared;
      await open(tester, onKeep: (_) async {
        kept++;
        return true;
      }, onShare: (_, c) async {
        shared = c;
        return true;
      });
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect((await pushed()), ReviewOutcome.kept);
      expect(kept, 1);
      expect(shared, isNull);

      await open(tester, onShare: (_, c) async {
        shared = c;
        return true;
      });
      await tester.enterText(find.byKey(kShareReviewCaptionKey), 'Done.');
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect((await pushed()), ReviewOutcome.shared);
      expect(shared, 'Done.');
    });

    testWidgets('while it works the action says so, and a failure keeps the screen up', (tester) async {
      final gate = Completer<bool>();
      await open(tester, onKeep: (_) => gate.future);
      await tester.tap(find.text('Keep'));
      await tester.pump();
      expect(find.text('Keeping…'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget, reason: 'Share keeps its own name');
      gate.complete(false);
      await tester.pumpAndSettle();
      expect(find.byType(CaptureReviewScreen), findsOneWidget);
      expect(find.textContaining('Couldn’t save the photo'), findsOneWidget);
    });

    testWidgets('a session whose camera was skipped is the surface with the same text', (tester) async {
      await open(tester, withShot: false, share: ShareState.underTwentyHours);
      expect(find.byType(Image), findsNothing);
      expect(inCard('Spanish · 1h 20m'), findsOneWidget);
    });
  });

  group('selectedBandInOrder', () {
    Photo photo(int ts) => Photo(
      taskId: 't', taskName: 'T', dayKey: 'd', timestamp: ts, sessionSeconds: 1, photoUrl: '', storagePath: '',
    );
    test('keeps pool order whatever the tap order', () {
      final pool = [photo(1), photo(2), photo(3)];
      expect(selectedBandInOrder(pool, {pool[2].id, pool[0].id}).map((p) => p.timestamp), [1, 3]);
    });
  });
}

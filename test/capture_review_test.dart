import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/photos/capture_crop.dart';
import 'package:sondr/features/feed/widgets/story_card.dart' show NoPhotoFrame;
import 'package:sondr/features/photos/capture_review_screen.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/sondr_camera.dart';
import 'package:sondr/shared/sondr_action.dart';

/// The review screen: the shot at the size it was framed at, and the two
/// things that can be done with it.
void main() {
  const w13 = 390.0, h13 = 844.0;
  const scale = 0.9906137184115524;

  final shot = Uint8List.fromList(
    img.encodeJpg(img.Image(width: 30, height: 40), quality: 80),
  );

  Future<void> pumpReview(
    WidgetTester tester, {
    required ShareState share,
    List<Photo> band = const [],
    Future<bool> Function(WidgetRef)? onKeep,
    Future<bool> Function(WidgetRef, String?, List<Photo>)? onShare,
    double textScale = 1.0,
    bool withShot = true,
    int? milestoneHours,
  }) async {
    tester.view.physicalSize = const Size(w13 * 3, h13 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: CaptureReviewScreen(
            shot: withShot ? shot : null,
            milestoneHours: milestoneHours,
            taskName: 'Spanish',
            sessionLabel: '1h 20m',
            share: share,
            bandPhotos: band,
            onKeep: onKeep,
            onShare: onShare,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the photo occupies the viewfinder rect', (tester) async {
    await pumpReview(tester, share: ShareState.allowed);
    final photo = tester.getRect(find.byKey(kReviewPhotoKey));
    expect(photo.width, closeTo(w13 - 2 * kCameraSideInset * scale, 0.5));
    expect(photo.width, closeTo(342.5, 0.5));
    expect(photo.height, closeTo(456.6, 0.5));
    expect(photo.width / photo.height, closeTo(kCaptureAspect, 0.001));
    expect(photo.left, closeTo(kCameraSideInset * scale, 0.5));
  });

  testWidgets('past 20h: caption, then Share ABOVE Keep', (tester) async {
    await pumpReview(tester, share: ShareState.allowed);
    expect(find.text('Add a caption (optional)'), findsOneWidget);
    expect(find.text('Keep'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Sharing unlocks at 20h'), findsNothing);
    // Share leads, as the primary does in every other pair in the app.
    expect(
      tester.getRect(find.text('Share')).bottom,
      lessThan(tester.getRect(find.text('Keep')).top),
      reason: 'Keep is above Share',
    );
    expect(find.text('Retake'), findsOneWidget);
  });

  testWidgets('under 20h: no caption, no Share, and it says why', (
    tester,
  ) async {
    await pumpReview(tester, share: ShareState.underTwentyHours);
    expect(find.text('Sharing unlocks at 20h'), findsOneWidget);
    expect(find.text('Share'), findsNothing);
    expect(find.text('Add a caption (optional)'), findsNothing);
    expect(find.text('Keep'), findsOneWidget);
    // Keep is the primary here, not the supporting action.
    final keep = tester.widget<Text>(find.text('Keep'));
    expect(keep.style!.fontWeight, FontWeight.w700);
    expect(keep.style!.color, const Color(0xFFFAFAFA));
  });

  testWidgets('a guest is told what is missing, and it is not hours', (
    tester,
  ) async {
    await pumpReview(tester, share: ShareState.guest);
    expect(find.text('Create an account to share'), findsOneWidget);
    expect(find.text('Sharing unlocks at 20h'), findsNothing);
    expect(find.text('Share'), findsNothing);
    expect(find.text('Keep'), findsOneWidget);
  });

  testWidgets('a signed-in user under 20h is told about the hours', (
    tester,
  ) async {
    await pumpReview(tester, share: ShareState.underTwentyHours);
    expect(find.text('Sharing unlocks at 20h'), findsOneWidget);
    expect(find.text('Create an account to share'), findsNothing);
  });

  test('the locked copy answers the question that was asked', () {
    expect(ShareState.allowed.canShare, isTrue);
    expect(ShareState.guest.canShare, isFalse);
    expect(ShareState.underTwentyHours.canShare, isFalse);
    expect(ShareState.guest.lockedCopy, 'Create an account to share');
    expect(ShareState.underTwentyHours.lockedCopy, 'Sharing unlocks at 20h');
  });

  testWidgets('past 20h Keep is the quiet one', (tester) async {
    await pumpReview(tester, share: ShareState.allowed);
    final keep = tester.widget<Text>(find.text('Keep'));
    expect(keep.style!.fontWeight, FontWeight.w400);
    expect(keep.style!.color, const Color(0xFFB0B0B0));
  });

  testWidgets('retake goes back, and nothing is saved', (tester) async {
    var kept = 0, shared = 0;
    await pumpReview(
      tester,
      share: ShareState.allowed,
      onKeep: (_) async {
        kept++;
        return true;
      },
      onShare: (_, _, _) async {
        shared++;
        return true;
      },
    );
    await tester.tap(find.text('Retake'));
    await tester.pumpAndSettle();
    expect(kept, 0);
    expect(shared, 0);
  });

  testWidgets('Keep saves and does not post', (tester) async {
    var kept = 0, shared = 0;
    await pumpReview(
      tester,
      share: ShareState.allowed,
      onKeep: (_) async {
        kept++;
        return true;
      },
      onShare: (_, _, _) async {
        shared++;
        return true;
      },
    );
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(kept, 1);
    expect(shared, 0, reason: 'Keep posted something');
  });

  testWidgets('Share posts, with the caption', (tester) async {
    String? caption;
    await pumpReview(
      tester,
      share: ShareState.allowed,
      onShare: (_, text, _) async {
        caption = text;
        return true;
      },
    );
    await tester.enterText(find.byType(TextField), 'Finally fluent');
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(caption, 'Finally fluent');
  });

  group('the caption', () {
    testWidgets('has no counter, and reserves no room for one', (
      tester,
    ) async {
      await pumpReview(tester, share: ShareState.allowed);
      // Material's own "0/200", which this app never styled.
      expect(find.text('0/200'), findsNothing);
      expect(find.textContaining('/200'), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.maxLength, isNull, reason: 'maxLength draws the counter');
      expect(field.decoration!.counterText, isNull);

      // Nothing below the field but the actions: with maxLength set, an
      // empty field still kept a line for a counter nobody asked for.
      final caption = tester.getRect(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(TextField)), caption);
      expect(find.textContaining('/200'), findsNothing);
    });

    testWidgets('stops at 200, typed or pasted', (tester) async {
      String? sent;
      await pumpReview(
        tester,
        share: ShareState.allowed,
        onShare: (_, caption, _) async {
          sent = caption;
          return true;
        },
      );
      // A paste of 250 is truncated, not rejected.
      await tester.enterText(find.byType(TextField), 'x' * 250);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text.length,
        kCaptionMaxLength,
      );
      // And one character over the line is dropped, not refused: clear
      // first, because a field already AT the limit rejects a longer value
      // outright rather than truncating it.
      await tester.enterText(find.byType(TextField), '');
      await tester.enterText(find.byType(TextField), '${'y' * 200}z');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(sent!.length, kCaptionMaxLength);
      expect(sent, 'y' * 200);
    });
  });

  group('while it is working', () {
    /// An action that does not finish until released, so the busy state can
    /// be looked at.
    (Future<bool> Function(WidgetRef), void Function()) held() {
      final completer = Completer<bool>();
      return ((_) => completer.future, () => completer.complete(true));
    }

    testWidgets('Keep says "Keeping…" and Share keeps its own name', (
      tester,
    ) async {
      final (onKeep, release) = held();
      await pumpReview(
        tester,
        share: ShareState.allowed,
        onKeep: onKeep,
      );
      await tester.tap(find.text('Keep'));
      await tester.pump();

      expect(find.text('Keeping…'), findsOneWidget);
      expect(find.text('Keep'), findsNothing);
      // The action nobody chose does not narrate.
      expect(find.text('Share'), findsOneWidget);
      expect(
        find.text('Sharing…'),
        findsNothing,
        reason: 'Keep made Share claim to be working',
      );
      // And it cannot be tapped while the other runs.
      expect(
        tester.widget<SondrAction>(find.byType(SondrAction).last).onPressed,
        isNull,
      );
      release();
      await tester.pumpAndSettle();
    });

    testWidgets('Share says "Sharing…" and Keep keeps its own name', (
      tester,
    ) async {
      final completer = Completer<bool>();
      await pumpReview(
        tester,
        share: ShareState.allowed,
        onShare: (_, _, _) => completer.future,
      );
      await tester.tap(find.text('Share'));
      await tester.pump();

      expect(find.text('Sharing…'), findsOneWidget);
      expect(find.text('Share'), findsNothing);
      expect(find.text('Keep'), findsOneWidget);
      expect(find.text('Keeping…'), findsNothing);
      completer.complete(true);
      await tester.pumpAndSettle();
    });

    testWidgets('the keep-only variant says "Keeping…" too', (tester) async {
      final (onKeep, release) = held();
      await pumpReview(
        tester,
        share: ShareState.underTwentyHours,
        onKeep: onKeep,
      );
      await tester.tap(find.text('Keep'));
      await tester.pump();
      expect(find.text('Keeping…'), findsOneWidget);
      // The old copy, which said what the code was doing rather than what
      // the person had asked for.
      expect(find.text('Saving…'), findsNothing);
      release();
      await tester.pumpAndSettle();
    });

    testWidgets('a guest keeping says the same', (tester) async {
      final (onKeep, release) = held();
      await pumpReview(tester, share: ShareState.guest, onKeep: onKeep);
      await tester.tap(find.text('Keep'));
      await tester.pump();
      expect(find.text('Keeping…'), findsOneWidget);
      release();
      await tester.pumpAndSettle();
    });
  });

  testWidgets('a failed save keeps the screen up and says so', (tester) async {
    await pumpReview(tester, share: ShareState.allowed, onKeep: (_) async => false);
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Couldn’t save'), findsOneWidget);
    expect(find.byKey(kReviewPhotoKey), findsOneWidget);
  });

  group('the milestone band row', () {
    final band = [
      for (var i = 0; i < 3; i++)
        Photo(
          taskId: 't',
          taskName: 'Spanish',
          dayKey: '2026-10-0${i + 1}',
          timestamp: 1000 + i,
          sessionSeconds: 600,
          photoUrl: 'https://example.test/$i.jpg',
          storagePath: 'p/$i',
        ),
    ];

    testWidgets('sits above the caption, not below it', (tester) async {
      await pumpReview(tester, share: ShareState.allowed, band: band);
      await tester.drag(find.byKey(kReviewPhotoKey), const Offset(0, -320));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(kBandRowKey)).bottom,
        lessThan(tester.getRect(find.byType(TextField)).top),
        reason: 'the caption is above the band row',
      );
    });

    testWidgets('starts with only the new photo in, the rest dimmed', (
      tester,
    ) async {
      await pumpReview(tester, share: ShareState.allowed, band: band);
      final row = find.byKey(kBandRowKey);
      expect(row, findsOneWidget);
      // Four thumbs: the capture plus three from the band.
      final opacities = tester
          .widgetList<Opacity>(
            find.descendant(of: row, matching: find.byType(Opacity)),
          )
          .map((o) => o.opacity)
          .toList();
      expect(opacities, [1.0, 0.35, 0.35, 0.35]);
      expect(tester.getSize(find.byKey(kBandRowKey)).height,
          closeTo(kBandThumb * scale, 0.5));
    });

    testWidgets('tapping toggles, and only the chosen ones are posted', (
      tester,
    ) async {
      List<Photo>? posted;
      await pumpReview(
        tester,
        share: ShareState.allowed,
        band: band,
        onShare: (_, _, also) async {
          posted = also;
          return true;
        },
      );
      // The row sits under a 456-tall photo, so it is below the fold on
      // this device — scroll to it as a thumb would.
      await tester.drag(find.byKey(kReviewPhotoKey), const Offset(0, -320));
      await tester.pumpAndSettle();

      final thumbs = find.descendant(
        of: find.byKey(kBandRowKey),
        matching: find.byType(Opacity),
      );
      await tester.tap(thumbs.at(2));
      await tester.pumpAndSettle();
      await tester.tap(thumbs.at(1));
      await tester.pumpAndSettle();
      await tester.tap(thumbs.at(1)); // and off again
      await tester.pumpAndSettle();

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      // Pool order, not tap order.
      expect(posted!.map((p) => p.id).toList(), [band[1].id]);
    });
  });

  group('a milestone with the camera skipped', () {
    testWidgets('shows the milestone frame where the photo would be, and '
        'still offers the band and Share', (tester) async {
      final band = [
        const Photo(
          taskId: 't', taskName: 'Spanish', dayKey: '2026-10-01',
          timestamp: 1, sessionSeconds: 0, photoUrl: 'assets/mock/sample1.jpg',
          storagePath: 'p',
        ),
      ];
      List<Photo>? shared;
      await pumpReview(
        tester,
        share: ShareState.allowed,
        band: band,
        withShot: false,
        milestoneHours: 20,
        onShare: (ref, caption, also) async {
          shared = also;
          return true;
        },
      );
      expect(find.byType(NoPhotoFrame), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
      expect(find.byKey(kBandRowKey), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);

      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(shared, isNotNull, reason: 'Share did nothing without a photo');
    });
  });
}

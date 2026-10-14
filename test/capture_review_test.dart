import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/photos/capture_crop.dart';
import 'package:sondr/features/photos/capture_review_screen.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/sondr_camera.dart';

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
    required bool canShare,
    List<Photo> band = const [],
    Future<bool> Function(WidgetRef)? onKeep,
    Future<bool> Function(WidgetRef, String?, List<Photo>)? onShare,
    double textScale = 1.0,
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
            shot: shot,
            taskName: 'Spanish',
            sessionLabel: '1h 20m',
            canShare: canShare,
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
    await pumpReview(tester, canShare: true);
    final photo = tester.getRect(find.byKey(kReviewPhotoKey));
    expect(photo.width, closeTo(w13 - 2 * kCameraSideInset * scale, 0.5));
    expect(photo.width, closeTo(342.5, 0.5));
    expect(photo.height, closeTo(456.6, 0.5));
    expect(photo.width / photo.height, closeTo(kCaptureAspect, 0.001));
    expect(photo.left, closeTo(kCameraSideInset * scale, 0.5));
  });

  testWidgets('past 20h: caption, then Keep ABOVE Share', (tester) async {
    await pumpReview(tester, canShare: true);
    expect(find.text('Add a caption (optional)'), findsOneWidget);
    expect(find.text('Keep'), findsOneWidget);
    expect(find.text('Share'), findsOneWidget);
    expect(find.text('Sharing unlocks at 20h'), findsNothing);
    // The order is deliberate and inverts the app's usual pair.
    expect(
      tester.getRect(find.text('Keep')).bottom,
      lessThan(tester.getRect(find.text('Share')).top),
      reason: 'Share is above Keep',
    );
    expect(find.text('retake'), findsOneWidget);
  });

  testWidgets('under 20h: no caption, no Share, and it says why', (
    tester,
  ) async {
    await pumpReview(tester, canShare: false);
    expect(find.text('Sharing unlocks at 20h'), findsOneWidget);
    expect(find.text('Share'), findsNothing);
    expect(find.text('Add a caption (optional)'), findsNothing);
    expect(find.text('Keep'), findsOneWidget);
    // Keep is the primary here, not the supporting action.
    final keep = tester.widget<Text>(find.text('Keep'));
    expect(keep.style!.fontWeight, FontWeight.w700);
    expect(keep.style!.color, const Color(0xFFFAFAFA));
  });

  testWidgets('past 20h Keep is the quiet one', (tester) async {
    await pumpReview(tester, canShare: true);
    final keep = tester.widget<Text>(find.text('Keep'));
    expect(keep.style!.fontWeight, FontWeight.w400);
    expect(keep.style!.color, const Color(0xFFB0B0B0));
  });

  testWidgets('retake goes back, and nothing is saved', (tester) async {
    var kept = 0, shared = 0;
    await pumpReview(
      tester,
      canShare: true,
      onKeep: (_) async {
        kept++;
        return true;
      },
      onShare: (_, _, _) async {
        shared++;
        return true;
      },
    );
    await tester.tap(find.text('retake'));
    await tester.pumpAndSettle();
    expect(kept, 0);
    expect(shared, 0);
  });

  testWidgets('Keep saves and does not post', (tester) async {
    var kept = 0, shared = 0;
    await pumpReview(
      tester,
      canShare: true,
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
      canShare: true,
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

  testWidgets('a failed save keeps the screen up and says so', (tester) async {
    await pumpReview(tester, canShare: true, onKeep: (_) async => false);
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
      await pumpReview(tester, canShare: true, band: band);
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
      await pumpReview(tester, canShare: true, band: band);
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
        canShare: true,
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
}

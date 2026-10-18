import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/photos/screen_flash.dart';
import 'package:sondr/features/photos/sondr_camera.dart';
import 'package:sondr/shared/ring/progress_ring.dart';
import 'package:sondr/shared/ring/ring_metrics.dart';

/// The camera screen's geometry, on the device it was specified for.
void main() {
  const w13 = 390.0, h13 = 844.0, top13 = 47.0, bottom13 = 34.0;
  const scale = 0.9906137184115524;

  Future<_Fake> pumpCamera(
    WidgetTester tester, {
    double textScale = 1.0,
    CameraTrouble? trouble,
    bool hasFlash = true,
    bool canFlip = true,
    bool captureFails = false,
    Future<void> Function()? onOpenSettings,
    _FakeFlash? screenFlash,
  }) async {
    tester.view.physicalSize = const Size(w13 * 3, h13 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(
      top: top13 * 3,
      bottom: bottom13 * 3,
    );
    addTearDown(tester.view.reset);

    final fake = _Fake(
      trouble: trouble,
      flash: hasFlash,
      flip: canFlip,
      captureFails: captureFails,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: SondrCameraScreen(
          taskName: 'Spanish',
          sessionLabel: '1h 20m',
          ringProgress: 0.4,
          session: fake,
          onOpenSettings: onOpenSettings,
          screenFlash: screenFlash ?? _FakeFlash(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('the viewfinder is 3:4, inset 24, below the task line', (
    tester,
  ) async {
    await pumpCamera(tester);
    final finder = tester.getRect(find.byKey(kViewfinderKey));

    // 342 x 456 on this device.
    expect(finder.width, closeTo(w13 - 2 * 24 * scale, 0.5));
    expect(finder.width, closeTo(342.5, 0.5));
    expect(finder.height, closeTo(456.6, 0.5));
    expect(finder.width / finder.height, closeTo(3 / 4, 0.001));
    // Centred, with the inset either side.
    expect(finder.left, closeTo(24 * scale, 0.5));
    expect(w13 - finder.right, closeTo(24 * scale, 0.5));

    // 16 under the task line, which is itself 12 under the safe area.
    final task = tester.getRect(find.textContaining('Spanish'));
    expect(task.top, closeTo(top13 + 12 * scale, 0.6));
    expect(finder.top - task.bottom, closeTo(16 * scale, 0.6));
  });

  testWidgets('the shutter is the ring, at the shared weight', (tester) async {
    await pumpCamera(tester);
    final ring = tester.widget<ProgressRing>(find.byKey(kShutterKey));
    expect(ring.size, closeTo(72 * scale, 0.1));
    expect(ring.stroke, closeTo(ringStroke(scale), 0.01));
    expect(ring.progress, 0.4);

    final shutter = tester.getRect(find.byKey(kShutterKey));
    final finder = tester.getRect(find.byKey(kViewfinderKey));
    expect(shutter.top - finder.bottom, closeTo(24 * scale, 0.6));
    // Centred on the screen.
    expect(shutter.center.dx, closeTo(w13 / 2, 0.5));
  });

  testWidgets('Flash and Flip are 44 tall and centred on the shutter', (
    tester,
  ) async {
    await pumpCamera(tester);
    final shutter = tester.getRect(find.byKey(kShutterKey));
    for (final label in ['Flash off', 'Flip']) {
      final word = find.text(label);
      expect(word, findsOneWidget, reason: label);
      final box = tester.getRect(
        find.ancestor(of: word, matching: find.byType(ConstrainedBox)).first,
      );
      expect(box.height, greaterThanOrEqualTo(44 * scale - 0.01), reason: label);
      expect(box.width, greaterThanOrEqualTo(44 * scale - 0.01), reason: label);
      expect(box.center.dy, closeTo(shutter.center.dy, 0.5), reason: label);
    }
  });

  testWidgets('the words are anchored to the shutter, 32 either side', (
    tester,
  ) async {
    await pumpCamera(tester);
    final shutter = tester.getRect(find.byKey(kShutterKey));
    final gap = 32 * scale;

    // The WORD's near edge is a gap from the ring — not its tap target's,
    // which grows the other way.
    final flash = tester.getRect(find.textContaining('Flash'));
    final flip = tester.getRect(find.text('Flip'));
    expect(shutter.left - flash.right, closeTo(gap, 0.5));
    expect(flip.left - shutter.right, closeTo(gap, 0.5));

    // They used to sit against the screen instead: 16.7 from the left edge
    // and 105 from the ring.
    expect(flash.left, greaterThan(60));
    expect(390 - flip.right, greaterThan(60));

    // The tap targets reach 44 OUTWARD, away from the ring, so the near
    // edge of each is still the word's.
    Rect targetFor(Finder word) => tester.getRect(
      find.ancestor(of: word, matching: find.byType(ConstrainedBox)).first,
    );
    final flashTarget = targetFor(find.textContaining('Flash'));
    final flipTarget = targetFor(find.text('Flip'));
    expect(flashTarget.right, closeTo(flash.right, 0.5));
    expect(flashTarget.left, lessThanOrEqualTo(flash.left + 0.01));
    expect(flipTarget.left, closeTo(flip.left, 0.5));
    expect(flipTarget.right, greaterThanOrEqualTo(flip.right - 0.01));
  });

  testWidgets('cycling the flash moves neither the ring nor the word\'s end', (
    tester,
  ) async {
    await pumpCamera(tester);
    final shutter = tester.getRect(find.byKey(kShutterKey));
    final gap = 32 * scale;
    final viewfinder = tester.getRect(find.byKey(kViewfinderKey));
    final skip = tester.getRect(find.text('Skip'));

    for (final expected in ['Flash on', 'Flash auto', 'Flash off']) {
      await tester.tap(find.textContaining('Flash'));
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);

      // "flash auto" is half again as wide as "flash on"; the end of the
      // word and the ring both stay put, and so does everything else.
      final word = tester.getRect(find.text(expected));
      expect(
        shutter.left - word.right,
        closeTo(gap, 0.5),
        reason: 'the gap moved on "$expected"',
      );
      expect(tester.getRect(find.byKey(kShutterKey)), shutter);
      expect(tester.getRect(find.byKey(kViewfinderKey)), viewfinder);
      expect(tester.getRect(find.text('Skip')), skip);
    }
  });

  testWidgets('flash cycles off → on → auto → off', (tester) async {
    final fake = await pumpCamera(tester);
    for (final expected in ['Flash on', 'Flash auto', 'Flash off']) {
      await tester.tap(find.textContaining('Flash'));
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
    }
    // The leading `off` is the screen applying its initial state when the
    // camera opens — the lens must not keep a flash setting from last time.
    expect(fake.flashes, [
      CaptureFlash.off,
      CaptureFlash.on,
      CaptureFlash.auto,
      CaptureFlash.off,
    ]);
  });

  group('the front camera', () {
    testWidgets('offers two flash settings, not three', (tester) async {
      await pumpCamera(tester);
      await tester.tap(find.text('Flip'));
      await tester.pumpAndSettle();

      // off → on → off. "Auto" is a lamp reading the room, and the front
      // flash is the screen, which cannot.
      expect(find.text('Flash off'), findsOneWidget);
      await tester.tap(find.textContaining('Flash'));
      await tester.pumpAndSettle();
      expect(find.text('Flash on'), findsOneWidget);
      await tester.tap(find.textContaining('Flash'));
      await tester.pumpAndSettle();
      expect(find.text('Flash off'), findsOneWidget);
      expect(find.text('Flash auto'), findsNothing);
    });

    testWidgets('the rear keeps all three', (tester) async {
      await pumpCamera(tester);
      for (final expected in ['Flash on', 'Flash auto', 'Flash off']) {
        await tester.tap(find.textContaining('Flash'));
        await tester.pumpAndSettle();
        expect(find.text(expected), findsOneWidget);
      }
    });

    testWidgets('"on" survives a flip; "auto" becomes off', (tester) async {
      await pumpCamera(tester);
      // Rear, on → flip → still on.
      await tester.tap(find.textContaining('Flash'));
      await tester.pumpAndSettle();
      expect(find.text('Flash on'), findsOneWidget);
      await tester.tap(find.text('Flip'));
      await tester.pumpAndSettle();
      expect(find.text('Flash on'), findsOneWidget);

      // Back, on → auto → flip → off, rather than a silent always-on
      // screen flash.
      await tester.tap(find.text('Flip'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Flash'));
      await tester.pumpAndSettle();
      expect(find.text('Flash auto'), findsOneWidget);
      await tester.tap(find.text('Flip'));
      await tester.pumpAndSettle();
      expect(find.text('Flash off'), findsOneWidget);
    });

    testWidgets('a lit capture whitens the screen and puts it back', (
      tester,
    ) async {
      final flash = _FakeFlash();
      await pumpCamera(tester, screenFlash: flash);
      await tester.tap(find.text('Flip'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Flash'));
      await tester.pumpAndSettle();
      expect(find.text('Flash on'), findsOneWidget);
      expect(find.byKey(kScreenFlashKey), findsNothing);

      await tester.runAsync(() async {
        await tester.tap(find.byKey(kShutterKey));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();

      // Raised before the shutter and put back after, in that order.
      expect(flash.calls.take(2).toList(), ['raise', 'restore']);
      expect(flash.lit, isFalse, reason: 'the screen was left at full');
      // And the white sheet is gone before the review screen.
      expect(find.byKey(kScreenFlashKey), findsNothing);
    });

    testWidgets('a capture that fails still puts the screen back', (
      tester,
    ) async {
      // The screen stays mounted here, so dispose cannot be the thing that
      // restores it — this is the only test that proves the capture itself
      // does, and it is why the restore sits in a finally.
      final flash = _FakeFlash();
      await pumpCamera(tester, screenFlash: flash, captureFails: true);
      await tester.tap(find.text('Flip'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Flash'));
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.byKey(kShutterKey));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();

      // Still on the camera, and no longer white.
      expect(find.byKey(kViewfinderKey), findsOneWidget);
      expect(find.byKey(kScreenFlashKey), findsNothing);
      expect(flash.calls, ['raise', 'restore']);
      expect(flash.lit, isFalse, reason: 'the screen was left at full');
      // And the shutter works again.
      expect(find.byKey(kShutterKey), findsOneWidget);
    });

    testWidgets('an unlit capture leaves the screen alone', (tester) async {
      final flash = _FakeFlash();
      await pumpCamera(tester, screenFlash: flash);
      await tester.tap(find.text('Flip'));
      await tester.pumpAndSettle();
      // Front, flash OFF.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(kShutterKey));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      // Nothing was raised. A restore may arrive from dispose when the
      // route pops, which is the safety net and not this test's business.
      expect(flash.calls, isNot(contains('raise')));
      expect(find.byKey(kScreenFlashKey), findsNothing);
    });

    testWidgets('the REAR camera never whitens the screen', (tester) async {
      final flash = _FakeFlash();
      await pumpCamera(tester, screenFlash: flash);
      await tester.tap(find.textContaining('Flash'));
      await tester.pumpAndSettle();
      expect(find.text('Flash on'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.byKey(kShutterKey));
        await Future<void>.delayed(const Duration(milliseconds: 80));
      });
      await tester.pumpAndSettle();
      expect(
        flash.calls,
        isNot(contains('raise')),
        reason: 'the rear lamp used the screen',
      );
    });

    testWidgets('leaving the screen restores the brightness', (tester) async {
      final flash = _FakeFlash();
      await pumpCamera(tester, screenFlash: flash);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(flash.calls, contains('restore'));
    });
  });

  testWidgets('a camera with no flash shows no flash control', (tester) async {
    await pumpCamera(tester, hasFlash: false);
    expect(find.textContaining('Flash'), findsNothing);
    expect(find.text('Flip'), findsOneWidget);
  });

  testWidgets('one lens means no flip', (tester) async {
    await pumpCamera(tester, canFlip: false);
    expect(find.text('Flip'), findsNothing);
  });

  testWidgets('flip restarts on the other lens', (tester) async {
    final fake = await pumpCamera(tester);
    await tester.tap(find.text('Flip'));
    await tester.pumpAndSettle();
    expect(fake.starts, [false, true]);
  });

  testWidgets('denied shows the copy and the way out', (tester) async {
    var opened = 0;
    await pumpCamera(
      tester,
      trouble: CameraTrouble.denied,
      onOpenSettings: () async => opened++,
    );
    expect(find.text('Camera access is off.'), findsOneWidget);
    expect(find.text('Open Settings'), findsOneWidget);
    // No shutter to press when there is nothing to shoot.
    expect(find.byKey(kShutterKey), findsNothing);
    expect(find.text('Skip'), findsOneWidget);

    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(opened, 1, reason: 'Open Settings did not open settings');
  });

  testWidgets('the denied state offers Settings even with no launcher given', (
    tester,
  ) async {
    // The real one is wired by default; the button is never decoration.
    await pumpCamera(tester, trouble: CameraTrouble.denied);
    expect(find.text('Open Settings'), findsOneWidget);
  });

  testWidgets('the shutter captures, and the crop runs off the UI thread', (
    tester,
  ) async {
    final fake = await pumpCamera(tester);
    // compute() needs real async: under the fake clock the isolate never
    // completes, which is itself the proof that the crop left this thread.
    await tester.runAsync(() async {
      await tester.tap(find.byKey(kShutterKey));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(fake.captures, 1);
    expect(find.byKey(kViewfinderKey), findsNothing);
  });

  for (final ts in [0.824, 1.0, 1.235]) {
    testWidgets('everything clears the bottom safe area at textScale $ts', (
      tester,
    ) async {
      await pumpCamera(tester, textScale: ts);
      final skip = tester.getRect(find.text('Skip'));
      expect(
        skip.bottom,
        lessThanOrEqualTo(h13 - bottom13 + 0.5),
        reason: 'skip is under the home indicator at $ts',
      );
      final shutter = tester.getRect(find.byKey(kShutterKey));
      expect(shutter.bottom, lessThan(skip.top + 0.01));
      expect(tester.takeException(), isNull);
    });
  }
}

/// A camera that is not a camera.
class _Fake implements CameraSession {
  _Fake({
    this.trouble,
    bool flash = true,
    bool flip = true,
    this.captureFails = false,
  }) : hasFlash = flash,
       canFlip = flip;

  /// A camera that cannot take the shot — the screen stays put afterwards.
  final bool captureFails;

  final CameraTrouble? trouble;
  @override
  final bool hasFlash;
  @override
  final bool canFlip;

  final List<bool> starts = [];
  final List<CaptureFlash> flashes = [];
  bool _front = false;
  int captures = 0;

  @override
  bool get isFront => _front;

  @override
  Future<CameraTrouble?> start({bool front = false}) async {
    starts.add(front);
    _front = front;
    return trouble;
  }

  /// What the screen would have done.
  int raises = 0;
  int restores = 0;

  @override
  Widget preview(BuildContext context) => const SizedBox.expand();

  @override
  Future<Uint8List?> capture() async {
    captures++;
    if (captureFails) return null;
    // Not a decodable image: the screen must still pop something.
    return Uint8List.fromList(List.filled(32, 7));
  }

  @override
  Future<void> setFlash(CaptureFlash flash) async => flashes.add(flash);

  @override
  Future<void> stop() async {}
}


/// The screen flash, without a screen.
class _FakeFlash implements ScreenFlash {
  final List<String> calls = [];
  bool lit = false;

  @override
  Future<void> raise() async {
    calls.add('raise');
    lit = true;
  }

  @override
  Future<void> restore() async {
    calls.add('restore');
    lit = false;
  }
}

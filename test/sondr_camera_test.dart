import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
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
    Future<void> Function()? onOpenSettings,
  }) async {
    tester.view.physicalSize = const Size(w13 * 3, h13 * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(
      top: top13 * 3,
      bottom: bottom13 * 3,
    );
    addTearDown(tester.view.reset);

    final fake = _Fake(trouble: trouble, flash: hasFlash, flip: canFlip);
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

  testWidgets('flash and flip are 44 tall and centred on the shutter', (
    tester,
  ) async {
    await pumpCamera(tester);
    final shutter = tester.getRect(find.byKey(kShutterKey));
    for (final label in ['flash off', 'flip']) {
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

  testWidgets('flash cycles off → on → auto → off', (tester) async {
    final fake = await pumpCamera(tester);
    for (final expected in ['flash on', 'flash auto', 'flash off']) {
      await tester.tap(find.textContaining('flash'));
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

  testWidgets('a camera with no flash shows no flash control', (tester) async {
    await pumpCamera(tester, hasFlash: false);
    expect(find.textContaining('flash'), findsNothing);
    expect(find.text('flip'), findsOneWidget);
  });

  testWidgets('one lens means no flip', (tester) async {
    await pumpCamera(tester, canFlip: false);
    expect(find.text('flip'), findsNothing);
  });

  testWidgets('flip restarts on the other lens', (tester) async {
    final fake = await pumpCamera(tester);
    await tester.tap(find.text('flip'));
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
    expect(find.text('skip'), findsOneWidget);

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
      final skip = tester.getRect(find.text('skip'));
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
  _Fake({this.trouble, bool flash = true, bool flip = true})
    : hasFlash = flash,
      canFlip = flip;

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

  @override
  Widget preview(BuildContext context) => const SizedBox.expand();

  @override
  Future<Uint8List?> capture() async {
    captures++;
    // Not a decodable image: the screen must still pop something.
    return Uint8List.fromList(List.filled(32, 7));
  }

  @override
  Future<void> setFlash(CaptureFlash flash) async => flashes.add(flash);

  @override
  Future<void> stop() async {}
}

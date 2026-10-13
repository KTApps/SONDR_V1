import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/debug/position_readout.dart';

import 'support/app_viewport.dart';

/// The QA position readout: present on the measured screens, off by default,
/// and gated on kDebugTools rather than kDebugMode.
///
/// That last part is what this file is really for. Tests run in DEBUG, so a
/// gate written as kDebugMode would be TRUE here — the overlay would draw,
/// and these tests would fail. A gate written as kDebugTools is const-false
/// without --dart-define=DEBUG_TOOLS=true, which is every normal build.
const _box = Key('probe-box');

void main() {
  Future<Rect> pump(WidgetTester tester, {required bool readoutOn}) async {
    useReferenceViewport(tester);
    // A fresh scope each time: Riverpod will not let the number of overrides
    // change under a mounted one.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (readoutOn)
            positionReadoutProvider.overrideWith(_AlwaysOn.new),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: PositionReadout(
            title: 'HOST',
            targets: () => [
              ReadoutTarget('box', probeType('SizedBox')),
            ],
            child: const Scaffold(
              body: Center(
                child: SizedBox(
                  key: _box,
                  width: 100,
                  height: 40,
                  child: ColoredBox(color: Color(0xFF161616)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tester.getRect(find.byKey(_box));
  }

  testWidgets('is off by default', (tester) async {
    await pump(tester, readoutOn: false);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(PositionReadout)),
    );
    expect(container.read(positionReadoutProvider), isFalse);
  });

  testWidgets('draws nothing and moves nothing when off', (tester) async {
    final box = await pump(tester, readoutOn: false);
    expect(find.textContaining('top/centre/bottom'), findsNothing);
    // Dead centre of the reference canvas, exactly as if the readout were
    // not in the tree at all.
    expect(box.center.dx, closeTo(kRefWidth / 2, 0.01));
    expect(box.center.dy, closeTo(kRefHeight / 2, 0.01));
    expect(box.size, const Size(100, 40));
  });

  testWidgets('stays silent when switched ON in a build without DEBUG_TOOLS, '
      'which is what the kDebugTools gate buys', (tester) async {
    final off = await pump(tester, readoutOn: false);
    final on = await pump(tester, readoutOn: true);
    expect(find.textContaining('top/centre/bottom'), findsNothing);
    // Byte-for-byte the same geometry: the switch cannot reach the layout.
    expect(on, off);
  });
}

class _AlwaysOn extends PositionReadoutToggle {
  @override
  bool build() => true;
}

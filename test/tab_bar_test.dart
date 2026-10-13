import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/shell/main_shell.dart';

/// The bottom tab bar.
///
/// It used to be an InkWell, and Material ink draws a HIGHLIGHT over the whole
/// of its bounds as well as the ripple. The bounds were the full tab cell, so
/// every tap flashed a grey rectangle across the tab.
final _bar = GlobalKey();

void main() {
  /// The tab bar on its own — the real shell's tabs each want Firebase.
  Future<void> pumpBar(WidgetTester tester, {required int index}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [selectedTabProvider.overrideWith(() => _PinnedTab(index))],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: const SizedBox.shrink(),
              bottomNavigationBar: RepaintBoundary(
                key: _bar,
                child: TextTabBar(
                  currentIndex: ref.watch(selectedTabProvider),
                  onSelect: ref.read(selectedTabProvider.notifier).set,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// What the tab bar actually PAINTS, as pixels.
  ///
  /// A live InkSplash or InkHighlight is not in the render tree — Material
  /// keeps them in a private list and paints them directly — so the only
  /// honest way to ask "did anything flash" is to rasterise the bar and look.
  Future<Uint8List> paintedPixels(WidgetTester tester) async {
    final boundary =
        _bar.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    late Uint8List bytes;
    await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      bytes = data!.buffer.asUint8List();
      image.dispose();
    });
    return bytes;
  }

  testWidgets('holding a tab down paints nothing', (tester) async {
    await pumpBar(tester, index: 0);
    final atRest = await paintedPixels(tester);

    // Press and HOLD. The highlight is what the report described — a
    // rectangle over the tab — and it appears on press, before any release.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Feed')),
    );
    await tester.pump(const Duration(milliseconds: 150));
    expect(
      await paintedPixels(tester),
      atRest,
      reason: 'something was painted while the tab was held down',
    );

    // And through the release, where a ripple would still be expanding.
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 50));
    final onRelease = await paintedPixels(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      await paintedPixels(tester),
      onRelease,
      reason: 'something was still animating after the tap',
    );
  });

  testWidgets('the tab still switches', (tester) async {
    await pumpBar(tester, index: 0);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();

    // Selected is bold; the others are not.
    TextStyle styleOf(String label) =>
        tester.widget<Text>(find.text(label)).style!;
    expect(styleOf('Profile').fontWeight, FontWeight.w700);
    expect(styleOf('Home').fontWeight, FontWeight.w500);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(styleOf('Home').fontWeight, FontWeight.w700);
  });

  testWidgets('the tap target is the whole cell, not just the label', (
    tester,
  ) async {
    await pumpBar(tester, index: 0);
    final label = tester.getRect(find.text('Feed'));
    // A point inside the middle cell but well clear of the glyphs — the top
    // of the bar, above the text. An InkWell filled the cell; so must this.
    final hit = Offset(label.center.dx, label.top - 6);
    await tester.tapAt(hit);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.text('Feed')).style!.fontWeight,
      FontWeight.w700,
      reason: 'the dead zone above the label used to be tappable',
    );
  });

  testWidgets('the selected tab keeps its underline and colours', (
    tester,
  ) async {
    await pumpBar(tester, index: 1);
    final underlines = tester.widgetList<Container>(
      find.descendant(
        of: find.byType(TextTabBar),
        matching: find.byType(Container),
      ),
    );
    final colours = underlines
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .toList();
    // Exactly one is painted; the other two are transparent.
    expect(colours.where((c) => c == Colors.transparent).length, 2);
    expect(colours.where((c) => c != Colors.transparent).length, 1);
    expect(tester.getSize(find.byType(TextTabBar)).height, greaterThan(0));
  });
}

class _PinnedTab extends SelectedTab {
  _PinnedTab(this.initial);
  final int initial;
  @override
  int build() => initial;
}

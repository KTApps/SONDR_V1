import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/history/day_detail_sheet.dart';
import 'package:sondr/features/history/history_providers.dart';
import 'package:sondr/features/photos/photos_repository.dart';

import 'support/app_viewport.dart';

/// The day-detail sheet answers the text-size setting, all of it.
///
/// Reported as a bug — the task name looked fixed on a device — and it is
/// not one: nothing in this app disables or clamps the scaler, and every
/// line in this sheet measures larger as the setting goes up. These are
/// the numbers, pinned, so that if anything ever does stop scaling it is
/// this that says so rather than a device.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required double textScale,
    String taskName = 'Golf',
  }) async {
    useReferenceViewport(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dayHistoryProvider.overrideWith(
            (ref, dayKey) => DayHistory(
              dayKey: dayKey,
              segments: const [3600],
              taskTimes: [TaskTime(name: taskName, seconds: 3600)],
              habits: null,
            ),
          ),
          photosForDayProvider.overrideWith((ref, dayKey) async => const []),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(kRefWidth, kRefHeight),
              textScaler: TextScaler.linear(textScale),
            ),
            child: const Scaffold(body: DayDetailSheet(dayKey: '2026-10-01')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// What a line is actually painted at: the declared size times the
  /// setting the paragraph was given.
  double painted(WidgetTester tester, Finder f) {
    final p = tester.renderObject<RenderParagraph>(f);
    return p.textScaler.scale(p.text.style!.fontSize!);
  }

  group('the task name', () {
    const sizes = [
      (scale: 0.824, points: 12.36, box: 17.0),
      (scale: 1.0, points: 15.0, box: 21.0),
      (scale: 1.235, points: 18.525, box: 26.0),
    ];

    for (final s in sizes) {
      testWidgets('is ${s.points} points at ${s.scale}', (tester) async {
        await pump(tester, textScale: s.scale);
        expect(painted(tester, find.text('Golf')), closeTo(s.points, 0.01));
        expect(
          tester.getRect(find.text('Golf')).height,
          closeTo(s.box, 0.5),
        );
      });
    }

    testWidgets('grows with every other line in the sheet', (tester) async {
      double heightsAt(WidgetTester t) => t.getRect(find.text('Golf')).height;
      await pump(tester, textScale: 0.824);
      final small = heightsAt(tester);
      await pump(tester, textScale: 1.235);
      final large = heightsAt(tester);
      expect(large, greaterThan(small * 1.2));

      // And it is not alone: the date, the figure in the ring, the label
      // under it and the section heading all answer the same setting.
      for (final line in ['Time per task', 'Logged']) {
        expect(painted(tester, find.text(line)), greaterThan(13.0),
            reason: line);
      }
    });
  });

  group('a name too long for its row', () {
    testWidgets('wraps — it does not ellipsise, and cannot overflow', (
      tester,
    ) async {
      const long = 'A very long task name that will not fit on one line';
      await pump(tester, textScale: 1.235, taskName: long);

      expect(tester.takeException(), isNull);
      final name = tester.widget<Text>(find.text(long));
      // Wrapping is what it does: no maxLines, no ellipsis, and the box is
      // taller than one line because of it.
      expect(name.maxLines, isNull);
      expect(name.overflow, isNull);
      expect(tester.getRect(find.text(long)).height, greaterThan(40));

      // The duration beside it stays on the row, inside the gutter, and
      // the two do not meet.
      final nameBox = tester.getRect(find.text(long));
      // Two "1h" on the sheet: the figure in the ring, and this row's.
      final time = tester.getRect(find.text('1h').last);
      expect(nameBox.right, lessThanOrEqualTo(time.left + 0.5));
      expect(time.right, lessThanOrEqualTo(kRefWidth - 24 + 0.5));
    });
  });
}

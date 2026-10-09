import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/features/habits/habits_providers.dart';
import 'package:sondr/features/habits/habits_screen.dart';
import 'package:sondr/shared/ring/progress_ring.dart';
import 'package:sondr/shared/ring/ring_metrics.dart';
import 'package:sondr/shared/ring/segmented_dial.dart';

/// One weight and one fill language for every ring in the app.
///
/// The dials used to carry their own thickness (the mini rings were 14% of
/// their diameter against the profile emblem's 5.4%) and their own hex
/// constants (#777777 filled, #232323 empty) rather than the tokens. These
/// tests pin the weight rule at every size the dials appear at, and the tones
/// at their source.
void main() {
  group('the weight rule', () {
    SegmentedDial dial({required double size, bool compact = false}) =>
        SegmentedDial(
          size: size,
          compact: compact,
          taskTodaySeconds: const [],
          habitStates: const [],
        );

    test('EVERY band is the thin ratio of its own diameter', () {
      // Each surface the dial appears on: home 260, day-detail 200, the
      // last-10-days cell 57, a calendar day 49.
      for (final probe in [
        dial(size: 260),
        dial(size: 200),
        dial(size: 57, compact: true),
        dial(size: 49, compact: true),
      ]) {
        expect(
          probe.outerStroke / probe.outerDiameter,
          closeTo(kThinRingStrokeRatio, 1e-9),
          reason: 'outer band at size ${probe.size}',
        );
        expect(
          probe.innerStroke / probe.innerDiameter,
          closeTo(kThinRingStrokeRatio, 1e-9),
          reason: 'inner band at size ${probe.size}',
        );
      }
    });

    test('the ratio is the one the profile and milestone rings use', () {
      expect(kThinRingStrokeRatio, closeTo(3 / 56, 1e-9));
      // ≈5.4%, and the home dial is no longer the heavy outlier it was: the
      // old mini stroke was 7 on a 50 ring, a shade over 14%.
      expect(kThinRingStrokeRatio, inInclusiveRange(0.05, 0.06));
      expect(dial(size: 57, compact: true).outerStroke, lessThan(7));
    });

    test('a standalone habits ring takes the same weight', () {
      expect(const HabitsRing(states: []).stroke, closeTo(44 * 3 / 56, 1e-9));
      expect(
        const HabitsRing(states: [], size: 120).stroke / 120,
        closeTo(kThinRingStrokeRatio, 1e-9),
      );
    });
  });

  group('the fill language', () {
    testWidgets('grey is in progress, white is reached, track is neither', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) {
              final t = GreyscaleTokens.of(context);
              // The three tones the whole grammar is built from.
              expect(t.ringFillInner, const Color(0xFFADADAD)); // in progress
              expect(t.ringFillOuter, const Color(0xFFFAFAFA)); // reached
              expect(t.ringTrack, const Color(0xFF3A3A3A)); // neither
              return const SizedBox();
            },
          ),
        ),
      );
    });

    test('the clamp still governs every progress indicator', () {
      expect(shownProgress(0), 0);
      expect(shownProgress(0.01), kProgressFloor);
      expect(shownProgress(1), kProgressCeiling);
    });
  });

  group('the habits page', () {
    Future<void> pumpHabits(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(theme: AppTheme.dark(), home: const HabitsScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    TextStyle styleOf(WidgetTester tester, String name) =>
        tester.widget<Text>(find.text(name)).style!;

    HabitsRing ringOf(WidgetTester tester) =>
        tester.widget<HabitsRing>(find.byType(HabitsRing));

    testWidgets('the day is the title and the date is the subline', (
      tester,
    ) async {
      await pumpHabits(tester);
      final now = DateTime.now();
      expect(find.text(DayKey.weekday(now.weekday)), findsOneWidget);
      expect(
        find.text('${now.day} ${DayKey.monthName(now.month)}'),
        findsOneWidget,
      );
      // Neither label the ring already carries.
      expect(find.text('Habits'), findsNothing);
      expect(find.textContaining('of'), findsNothing);
    });

    testWidgets('the name carries the state, and nothing else does', (
      tester,
    ) async {
      await pumpHabits(tester);
      // The local seed checks the first two habits today.
      final done = styleOf(tester, '6AM wake');
      final notDone = styleOf(tester, 'Cold shower');

      expect(done.fontWeight, FontWeight.w700);
      expect(notDone.fontWeight, FontWeight.w400);
      expect(done.color, const Color(0xFFFAFAFA));
      expect(notDone.color, const Color(0xFFB0B0B0));
      // No circle, no box, no strike-through.
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(ProgressRing), findsNothing);
      expect(done.decoration, anyOf(isNull, TextDecoration.none));
    });

    testWidgets('tapping a row marks it done, tapping again undoes it', (
      tester,
    ) async {
      await pumpHabits(tester);
      expect(ringOf(tester).states, [true, true, false, false, false]);

      await tester.tap(find.text('Cold shower'));
      await tester.pumpAndSettle();
      expect(styleOf(tester, 'Cold shower').fontWeight, FontWeight.w700);
      // The ring IS the dial's inner band: the segment fills with the row.
      expect(ringOf(tester).states, [true, true, true, false, false]);

      await tester.tap(find.text('Cold shower'));
      await tester.pumpAndSettle();
      expect(styleOf(tester, 'Cold shower').fontWeight, FontWeight.w400);
      expect(ringOf(tester).states, [true, true, false, false, false]);
    });

    testWidgets('the streak is a bare number, and absent at zero', (
      tester,
    ) async {
      await pumpHabits(tester);
      // The seed completes the previous three days, so every habit reads 3.
      expect(find.text('3'), findsNWidgets(5));
      expect(find.textContaining('day streak'), findsNothing);
      expect(find.text('0'), findsNothing);

      // A habit added today has no run behind it, so it shows nothing.
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HabitsScreen)),
      );
      await container.read(habitsProvider.notifier).addHabit('Journal');
      await tester.pumpAndSettle();
      expect(find.text('Journal'), findsOneWidget);
      expect(find.text('3'), findsNWidgets(5)); // still only the seeded five
      expect(find.text('0'), findsNothing);
    });

    testWidgets('both foot actions are there, and both are quiet', (
      tester,
    ) async {
      await pumpHabits(tester);
      expect(find.text('Add habit'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      for (final label in ['Add habit', 'Back']) {
        expect(styleOf(tester, label).color, const Color(0xFFB0B0B0));
      }
    });
  });
}

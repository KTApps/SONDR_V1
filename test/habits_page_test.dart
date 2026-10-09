import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/features/habits/habits_providers.dart';
import 'package:sondr/features/habits/habits_screen.dart';
import 'package:sondr/shared/ring/segmented_dial.dart';

/// Today's habits as a full page.
///
/// The dials' own weights and tones are deliberate and hand-tuned, and are not
/// this page's business. What IS pinned here is the list's own ladder:
/// completing a habit brightens its name by exactly one step — tertiary to
/// secondary — and never reaches white, because white is a milestone reached
/// and a habit is not one.
const Color _secondary = Color(0xFFB0B0B0);
const Color _tertiary = Color(0xFF6E6E6E);
const Color _white = Color(0xFFFAFAFA);

void main() {
  group('the summary band', () {
    test('takes the dial band weight', () {
      // 7 on a 57 box, the compact dial proportion, at whatever size.
      expect(const HabitsRing(states: []).stroke, closeTo(44 * 7 / 57, 1e-9));
      expect(
        const HabitsRing(states: [], size: 57).stroke,
        closeTo(7, 1e-9),
      );
    });
  });

  group('the page', () {
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

    testWidgets('completing a habit brightens its name one step', (
      tester,
    ) async {
      await pumpHabits(tester);
      // The local seed checks the first two habits today.
      final done = styleOf(tester, '6AM wake');
      final notDone = styleOf(tester, 'Cold shower');

      expect(notDone.color, _tertiary);
      expect(done.color, _secondary);
      // Up the ladder, not to the top of it, and not to the dial's fill grey.
      expect(done.color, isNot(_white));
      expect(done.color, isNot(const Color(0xFF777777)));
      // The weight moves with it.
      expect(done.fontWeight, FontWeight.w700);
      expect(notDone.fontWeight, FontWeight.w400);
      // No circle, no box, no strike-through.
      expect(find.byType(Checkbox), findsNothing);
      expect(done.decoration, anyOf(isNull, TextDecoration.none));
    });

    testWidgets('tapping a row marks it done, tapping again undoes it', (
      tester,
    ) async {
      await pumpHabits(tester);
      expect(ringOf(tester).states, [true, true, false, false, false]);

      await tester.tap(find.text('Cold shower'));
      await tester.pumpAndSettle();
      expect(styleOf(tester, 'Cold shower').color, _secondary);
      // The summary ring IS the dial's inner band: the segment fills with the
      // row, in the dial's own grey.
      expect(ringOf(tester).states, [true, true, true, false, false]);

      await tester.tap(find.text('Cold shower'));
      await tester.pumpAndSettle();
      expect(styleOf(tester, 'Cold shower').color, _tertiary);
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
        expect(styleOf(tester, label).color, _secondary);
      }
    });
  });
}

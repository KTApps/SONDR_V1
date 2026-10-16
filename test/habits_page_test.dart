import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/core/utils/figma_scale.dart';
import 'package:sondr/features/habits/habits_providers.dart';
import 'package:sondr/features/habits/habits_screen.dart';
import 'package:sondr/features/timer/timer_screen.dart';
import 'package:sondr/shared/sondr_field.dart';
import 'package:sondr/shared/sondr_swipe_row.dart';

import 'support/app_viewport.dart';

/// Today's habits, plain: a weekday, a centred list of names, "add habit".
///
/// The names are the whole screen, so what is pinned here is the names — their
/// tone, their casing, the number that trails them, and the three things you
/// can do to one.
const Color _white = Color(0xFFFAFAFA);
const Color _tertiary = Color(0xFF6E6E6E);

void main() {
  Future<void> pumpHabits(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.dark(), home: const HabitsScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The styled run inside a name, which is a [Text.rich] — the habit and its
  /// streak share one Text so they share a baseline.
  TextStyle nameStyle(WidgetTester tester, String habit) {
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((t) => t.textSpan?.toPlainText().startsWith(habit) ?? false);
    return (text.textSpan! as TextSpan).children!.first.style!;
  }

  double y(WidgetTester tester, String plainText) =>
      tester.getCenter(find.text(plainText)).dy;

  group('the screen', () {
    testWidgets('is an overlay, with no handle and no Back', (tester) async {
      await pumpHabits(tester);
      expect(find.byType(BackdropFilter), findsOneWidget);
      expect(find.text('Back'), findsNothing);
      // No sheet handle: a handle promises a drag this is not.
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Container &&
              (w.decoration as BoxDecoration?)?.borderRadius != null &&
              (w.constraints?.maxHeight ?? 99) < 8,
        ),
        findsNothing,
      );
    });

    testWidgets('the weekday is the whole header', (tester) async {
      await pumpHabits(tester);
      final now = DateTime.now();
      expect(find.text(DayKey.weekday(now.weekday)), findsOneWidget);
      // No date, no label, no summary ring.
      expect(
        find.text('${now.day} ${DayKey.monthName(now.month)}'),
        findsNothing,
      );
      expect(find.text('Habits'), findsNothing);
    });

    Future<void> pumpPushed(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => showHabitsScreen(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(HabitsScreen), findsOneWidget);
    }

    testWidgets('a tap on the backdrop dismisses it', (tester) async {
      await pumpPushed(tester);
      // Just under the weekday, clear of every control.
      await tester.tapAt(const Offset(40, 170));
      await tester.pumpAndSettle();
      expect(find.byType(HabitsScreen), findsNothing);
    });

    testWidgets('a downward swipe dismisses it', (tester) async {
      await pumpPushed(tester);
      await tester.dragFrom(const Offset(40, 170), const Offset(0, 140));
      await tester.pumpAndSettle();
      expect(find.byType(HabitsScreen), findsNothing);
    });

  });

  group('it lands on Home\'s lines', () {
    /// Pumps a screen at the reference device and reports the y of one of its
    /// texts. Both screens position globally, so the two are comparable.
    Future<double> yOf(
      WidgetTester tester,
      Widget screen,
      String text,
    ) async {
      final previous = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exception.toString().contains('No Firebase App')) return;
        previous?.call(d);
      };
      addTearDown(() => FlutterError.onError = previous);
      useReferenceViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: screen,
              bottomNavigationBar: const SizedBox(
                height: kTabBarHeight + kRefBottomInset,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return tester.getTopLeft(find.text(text)).dy;
    }

    testWidgets('the weekday sits where Home puts its title, at its size', (
      tester,
    ) async {
      final home = await yOf(tester, const TimerScreen(), 'Task');
      final homeSize = tester.widget<Text>(find.text('Task')).style!.fontSize;

      final day = DayKey.weekday(DateTime.now().weekday);
      final habits = await yOf(tester, const HabitsScreen(), day);
      final habitsSize = tester.widget<Text>(find.text(day)).style!.fontSize;

      expect(habits, closeTo(home, 0.01));
      expect(habitsSize, homeSize);
    });

    testWidgets('"Add habit" sits where Home puts "View your progress"', (
      tester,
    ) async {
      final home = await yOf(tester, const TimerScreen(), 'View your progress');
      final habits = await yOf(tester, const HabitsScreen(), 'Add habit');
      expect(habits, closeTo(home, 0.01));
    });
  });

  group('a name', () {
    testWidgets('is white when done and grey when not', (tester) async {
      await pumpHabits(tester);
      // The local seed checks the first two habits today.
      expect(nameStyle(tester, '6AM wake').color, _white);
      expect(nameStyle(tester, 'Cold shower').color, _tertiary);
      // Large and plain, and nothing struck through it.
      final scale = figmaScale(tester.element(find.byType(HabitsScreen)));
      expect(
        nameStyle(tester, '6AM wake').fontSize,
        closeTo(27 * scale, 0.01),
      );
      expect(
        nameStyle(tester, '6AM wake').decoration,
        anyOf(isNull, TextDecoration.none),
      );
    });

    testWidgets('is horizontally centred, like the add field', (
      tester,
    ) async {
      await pumpHabits(tester);
      final width = tester.getSize(find.byType(HabitsScreen)).width;

      // Dead centre of the screen, not shoved against the trailing edge by
      // the swipe row's own alignment.
      expect(tester.getCenter(find.text('6AM wake 3')).dx, closeTo(width / 2, 1));

      // And the same centre the field's cursor uses.
      await tester.tap(find.text('Add habit'));
      await tester.pumpAndSettle();
      expect(
        tester.getCenter(find.byType(SondrField)).dx,
        closeTo(tester.getCenter(find.text('6AM wake 3')).dx, 1),
      );
    });

    testWidgets('is rendered as typed', (tester) async {
      await pumpHabits(tester);
      // Not lowercased, not capitalised — the name the user chose.
      expect(find.textContaining('6AM wake'), findsOneWidget);
      expect(find.textContaining('6am wake'), findsNothing);
    });

    testWidgets('carries its streak on the same line, and nothing at 0', (
      tester,
    ) async {
      await pumpHabits(tester);
      // The seed completes the previous three days, so each habit reads 3 —
      // in the SAME Text as the name, which is what shares the baseline.
      expect(find.text('6AM wake 3'), findsOneWidget);
      expect(find.text('Cold shower 3'), findsOneWidget);

      final container = ProviderScope.containerOf(
        tester.element(find.byType(HabitsScreen)),
      );
      await container.read(habitsProvider.notifier).addHabit('Journal');
      await tester.pumpAndSettle();
      // No run behind it yet, so the name stands alone.
      expect(find.text('Journal'), findsOneWidget);
      expect(find.text('Journal 0'), findsNothing);
    });

    testWidgets('tapping it toggles today, tapping again undoes it', (
      tester,
    ) async {
      await pumpHabits(tester);
      expect(nameStyle(tester, 'Cold shower').color, _tertiary);

      await tester.tap(find.text('Cold shower 3'));
      await tester.pumpAndSettle();
      expect(nameStyle(tester, 'Cold shower').color, _white);

      await tester.tap(find.text('Cold shower 3'));
      await tester.pumpAndSettle();
      expect(nameStyle(tester, 'Cold shower').color, _tertiary);
    });

    testWidgets('the toggle writes TODAY and leaves the past alone', (
      tester,
    ) async {
      await pumpHabits(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HabitsScreen)),
      );
      final today = DayKey.of(DateTime.now());
      final yesterday = DayKey.of(
        DateTime.now().subtract(const Duration(days: 1)),
      );
      final before = container.read(habitsProvider).value!;
      final pastBefore = before.days[yesterday]!.completed;

      await tester.tap(find.text('Cold shower 3'));
      await tester.pumpAndSettle();

      final after = container.read(habitsProvider).value!;
      expect(after.days[today]!.completed, before.days[today]!.completed + 1);
      expect(after.days[yesterday]!.completed, pastBefore);
    });
  });

  group('add', () {
    testWidgets('opens an invisible field where the first habit was', (
      tester,
    ) async {
      await pumpHabits(tester);
      expect(find.byType(SondrField), findsNothing);
      final firstBefore = y(tester, '6AM wake 3');

      await tester.tap(find.text('Add habit'));
      await tester.pumpAndSettle();

      final field = tester.widget<SondrField>(find.byType(SondrField));
      expect(field.filled, isFalse); // invisible until typed in
      expect(field.centered, isTrue);
      expect(field.autofocus, isTrue);
      // The habit that was on top has moved down to make room.
      expect(y(tester, '6AM wake 3'), greaterThan(firstBefore));
    });

    testWidgets('Enter adds the habit, and it takes the top slot', (
      tester,
    ) async {
      await pumpHabits(tester);
      await tester.tap(find.text('Add habit'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(SondrField), 'Read');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(SondrField), findsNothing); // closed again
      expect(find.text('Read'), findsOneWidget);
      // Above the habit that used to lead the list.
      expect(y(tester, 'Read'), lessThan(y(tester, '6AM wake 3')));
    });

    testWidgets('Enter on an empty field cancels', (tester) async {
      await pumpHabits(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HabitsScreen)),
      );
      final before = container.read(habitsProvider).value!.liveList.length;

      await tester.tap(find.text('Add habit'));
      await tester.pumpAndSettle();
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(find.byType(SondrField), findsNothing);
      expect(container.read(habitsProvider).value!.liveList.length, before);
    });
  });

  group('remove', () {
    testWidgets('is hidden until swiped, and deletes only on the tap', (
      tester,
    ) async {
      await pumpHabits(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HabitsScreen)),
      );
      final before = container.read(habitsProvider).value!.liveList.length;

      Finder tray() => find
          .descendant(
            of: find.byType(SondrSwipeRow),
            matching: find.text('Remove'),
          )
          .hitTestable();

      expect(tray(), findsNothing);

      // The app's one swipe direction: left, tray on the right.
      await tester.drag(find.text('Cold shower 3'), const Offset(-200, 0));
      await tester.pumpAndSettle();
      expect(tray(), findsOneWidget);
      // The gesture alone destroys nothing.
      expect(container.read(habitsProvider).value!.liveList.length, before);

      // Centred against the name, not pinned to the top of its row.
      expect(
        tester.getCenter(tray()).dy,
        closeTo(tester.getCenter(find.text('Cold shower 3')).dy, 1),
      );

      await tester.tap(tray());
      await tester.pumpAndSettle();
      expect(find.textContaining('Cold shower'), findsNothing);
      expect(container.read(habitsProvider).value!.liveList.length, before - 1);
    });
  });
}

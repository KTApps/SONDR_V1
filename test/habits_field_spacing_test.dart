import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/habits/habits_screen.dart';

import 'support/app_viewport.dart';

/// The add field is a habit's row: the same line box, the same air above
/// and below, so the cursor and the first habit are spaced like two
/// habits. At every text size.
void main() {
  for (final ts in [0.824, 1.0, 1.235]) {
    testWidgets('the field matches a habit row at $ts', (tester) async {
      useReferenceViewport(tester);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(ts)),
            child: child!,
          ),
          home: const HabitsScreen(),
        ),
      ));
      await tester.pumpAndSettle();
      // Two habits, then the field open above them. Newest first: the row
      // directly under the field is the one added last.
      for (final name in ['Alpha', 'Bravo']) {
        await tester.tap(find.text('Add habit'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), name);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Add habit'));
      await tester.pumpAndSettle();

      Rect text(String n) => tester.getRect(find.textContaining(n));
      Rect row(String n) => tester.getRect(
        find.ancestor(of: find.textContaining(n), matching: find.byType(Padding)).first,
      );
      final field = tester.getRect(find.byType(TextField));
      final fieldRow = tester.getRect(
        find.ancestor(of: find.byType(TextField), matching: find.byType(Padding)).last,
      );
      final first = text('Bravo'), second = text('Alpha');

      // The line box.
      expect(field.height, closeTo(first.height, 0.5), reason: 'field box vs habit text box');
      // The row.
      expect(fieldRow.height, closeTo(row('Bravo').height, 0.5), reason: 'field row vs habit row');
      // The gaps: cursor → first habit, as habit → habit.
      final fieldToFirst = first.top - field.bottom;
      final habitToHabit = second.top - first.bottom;
      expect(fieldToFirst, closeTo(habitToHabit, 0.5), reason: 'gap under the field vs between habits');
      // ignore: avoid_print
      print('AFTER ts=$ts field box h=${field.height.toStringAsFixed(1)} habit text h=${first.height.toStringAsFixed(1)} '
          'field row h=${fieldRow.height.toStringAsFixed(1)} habit row h=${row('Bravo').height.toStringAsFixed(1)} '
          'gap field→habit=${fieldToFirst.toStringAsFixed(1)} habit→habit=${habitToHabit.toStringAsFixed(1)}');
    });
  }
}

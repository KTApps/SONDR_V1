import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/features/history/calendar_screen.dart';
import 'package:sondr/features/history/day_detail_sheet.dart';
import 'package:sondr/features/history/history_providers.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';

void main() {
  test('DayKey.parse round-trips a key to its date', () {
    final d = DayKey.parse('2026-06-02');
    expect([d.year, d.month, d.day], [2026, 6, 2]);
  });

  test('dayHistory derives per-task times and the ring split for a day',
      () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    final tasks = await c.read(tasksProvider.future);
    final spanish = tasks.firstWhere((t) => t.name == 'Spanish');

    // Log a known amount today, then read that day's history.
    final now = DateTime.now();
    await c
        .read(tasksProvider.notifier)
        .logSeconds(spanish.id, 1800, now);

    final history = c.read(dayHistoryProvider(DayKey.of(now)));

    // The ring has one segment per task, in task order.
    expect(history.segments.length, tasks.length);
    // Spanish appears in the breakdown and total reflects the logged time.
    expect(history.taskTimes.any((t) => t.name == 'Spanish'), isTrue);
    expect(history.totalSeconds, greaterThanOrEqualTo(1800));
    // Sorted largest-first.
    for (var i = 1; i < history.taskTimes.length; i++) {
      expect(history.taskTimes[i - 1].seconds,
          greaterThanOrEqualTo(history.taskTimes[i].seconds));
    }
  });

  test('an empty day has no data', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    await c.read(tasksProvider.future);

    // A far-past day nothing was logged on.
    final history = c.read(dayHistoryProvider('2000-01-01'));
    expect(history.hasData, isFalse);
    expect(history.totalSeconds, 0);
  });

  testWidgets('CalendarScreen builds and shows the month grid', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(theme: AppTheme.dark(), home: const CalendarScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);
    // The redesign (commit 420bb08) dropped the "Your progress" title and the
    // weekday header for a month-labelled vertical scroll: assert the current
    // month's label and a day cell instead.
    final now = DateTime.now();
    expect(find.text('${DayKey.monthName(now.month)} ${now.year}'),
        findsWidgets); // month label
    expect(find.text('15'), findsWidgets); // a day cell in the grid
  });

  testWidgets('DayDetailSheet builds for today', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: DayDetailSheet(dayKey: DayKey.of(DateTime.now())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DayDetailSheet), findsOneWidget);
    expect(find.text('logged'), findsOneWidget);
  });
}

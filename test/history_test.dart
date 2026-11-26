import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/utils/date.dart';
import 'package:sondr/features/history/calendar_screen.dart';
import 'package:sondr/features/history/day_detail_sheet.dart';
import 'package:sondr/features/history/history_providers.dart';
import 'package:sondr/features/photos/models/photo.dart';
import 'package:sondr/features/photos/photo_viewer.dart';
import 'package:sondr/features/photos/photos_repository.dart';
import 'package:sondr/shared/cached_photo.dart';
import 'package:sondr/features/tasks/tasks_providers.dart';

import 'tiny_png.dart';

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
    // The redesign keeps "logged", lowercase, in the line under the date.
    expect(find.textContaining(' logged'), findsOneWidget);
  });

  // The day sheet no longer opens the photo viewer: its photos are a row
  // to scroll, and a long press deletes. See test/day_sheet_test.dart.
  testWidgets('a day\'s photo does not open the viewer', (tester) async {
    final factoryBefore = photoImageProviderFactory;
    photoImageProviderFactory = (_) => MemoryImage(tinyPng);
    addTearDown(() => photoImageProviderFactory = factoryBefore);
    final today = DayKey.of(DateTime.now());
    Photo photo(int ts) => Photo(
          taskId: 't', taskName: 'Golf', dayKey: today, timestamp: ts,
          sessionSeconds: 60, photoUrl: 'https://x/$ts.jpg', storagePath: '',
          cumulativeSeconds: ts,
        );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          photosForDayProvider.overrideWith((ref, key) async => [photo(1), photo(2)]),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: DayDetailSheet(dayKey: today)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final row = find.byKey(kDaySheetPhotosKey);
    await tester.tap(find.descendant(of: row, matching: find.byType(SondrPhoto)).first);
    await tester.pumpAndSettle();
    expect(find.byType(PhotoViewer), findsNothing);
  });
}

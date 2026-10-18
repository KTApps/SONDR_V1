import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/timer/still_going_sheet.dart';

/// The sheet that catches a session nobody stopped.
void main() {
  final start = DateTime(2026, 10, 18, 9, 14);

  Future<StillGoingAnswer?> openSheet(
    WidgetTester tester, {
    required DateTime startedAt,
    required DateTime now,
    String taskName = 'Spanish',
  }) async {
    StillGoingAnswer? answer;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async {
                  answer = await showStillGoingSheet(
                    context,
                    taskName: taskName,
                    elapsed: now.difference(startedAt),
                    startedAt: startedAt,
                    now: now,
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return answer;
  }

  testWidgets('it asks, and names the task, the length and the start', (
    tester,
  ) async {
    await openSheet(tester, startedAt: start, now: start.add(const Duration(hours: 4, minutes: 30)));
    expect(find.text('Still going?'), findsOneWidget);
    expect(
      find.textContaining('Spanish has been running for 4h 30m'),
      findsOneWidget,
    );
    expect(find.text('Keep going'), findsOneWidget);
    expect(find.text('Stop now'), findsOneWidget);
    expect(find.text('Set end time'), findsOneWidget);
  });

  testWidgets('tapping outside does not make the question go away', (
    tester,
  ) async {
    await openSheet(tester, startedAt: start, now: start.add(const Duration(hours: 4)));
    // The scrim, well above the sheet.
    await tester.tapAt(const Offset(200, 40));
    await tester.pumpAndSettle();
    expect(
      find.text('Still going?'),
      findsOneWidget,
      reason: 'the sheet was dismissed, leaving the timer running',
    );
  });

  testWidgets('"Keep going" closes with that answer', (tester) async {
    await openSheet(tester, startedAt: start, now: start.add(const Duration(hours: 4)));
    await tester.tap(find.text('Keep going'));
    await tester.pumpAndSettle();
    expect(find.text('Still going?'), findsNothing);
  });

  group('when it started', () {
    String sentenceFor(WidgetTester tester, DateTime startedAt, DateTime now) {
      final element = tester.element(find.byType(Scaffold));
      return startedAtSentence(element, startedAt, now);
    }

    testWidgets('today is just the time', (tester) async {
      await openSheet(tester, startedAt: start, now: start.add(const Duration(hours: 4)));
      final text = sentenceFor(tester, start, start.add(const Duration(hours: 4)));
      expect(text, isNot(contains('yesterday')));
      expect(text, isNot(contains('day,')));
      expect(find.textContaining('since $text.'), findsOneWidget);
    });

    testWidgets('yesterday says so', (tester) async {
      final yesterday = DateTime(2026, 10, 17, 21, 14);
      final now = DateTime(2026, 10, 18, 8);
      await openSheet(tester, startedAt: yesterday, now: now);
      expect(sentenceFor(tester, yesterday, now), startsWith('yesterday, '));
      expect(find.textContaining('since yesterday, '), findsOneWidget);
    });

    testWidgets('older says the weekday', (tester) async {
      // Thursday the 15th, read on Sunday the 18th.
      final older = DateTime(2026, 10, 15, 21, 14);
      final now = DateTime(2026, 10, 18, 8);
      expect(older.weekday, DateTime.thursday);
      await openSheet(tester, startedAt: older, now: now);
      expect(sentenceFor(tester, older, now), startsWith('Thursday, '));
      expect(find.textContaining('since Thursday, '), findsOneWidget);
    });
  });

  group('setting an end time', () {
    testWidgets('the wheel replaces the choices, and Back brings them back', (
      tester,
    ) async {
      await openSheet(tester, startedAt: start, now: start.add(const Duration(hours: 4)));
      await tester.tap(find.text('Set end time'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('still-going-wheel')), findsOneWidget);
      expect(find.textContaining('Log until '), findsOneWidget);
      expect(find.text('Keep going'), findsNothing);
      expect(find.text('Stop now'), findsNothing);

      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('still-going-wheel')), findsNothing);
      expect(find.text('Keep going'), findsOneWidget);
    });

    testWidgets('the wheel is bounded by the start and now', (tester) async {
      final now = start.add(const Duration(hours: 4));
      await openSheet(tester, startedAt: start, now: now);
      await tester.tap(find.text('Set end time'));
      await tester.pumpAndSettle();

      final wheel = tester.widget<CupertinoDatePicker>(
        find.byKey(const Key('still-going-wheel')),
      );
      expect(wheel.minimumDate, start.add(const Duration(minutes: 1)));
      expect(wheel.maximumDate, now);
      expect(wheel.initialDateTime, now);
      // Same day, so a time wheel is enough.
      expect(wheel.mode, CupertinoDatePickerMode.time);
    });

    testWidgets('a session across midnight shows the date too', (tester) async {
      final yesterday = DateTime(2026, 10, 17, 21, 14);
      final now = DateTime(2026, 10, 18, 8);
      await openSheet(tester, startedAt: yesterday, now: now);
      await tester.tap(find.text('Set end time'));
      await tester.pumpAndSettle();
      final wheel = tester.widget<CupertinoDatePicker>(
        find.byKey(const Key('still-going-wheel')),
      );
      expect(wheel.mode, CupertinoDatePickerMode.dateAndTime);
    });

    testWidgets('confirming returns the chosen end', (tester) async {
      final now = start.add(const Duration(hours: 4));
      StillGoingAnswer? answer;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async {
                    answer = await showStillGoingSheet(
                      context,
                      taskName: 'Spanish',
                      elapsed: const Duration(hours: 4),
                      startedAt: start,
                      now: now,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Set end time'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Log until '));
      await tester.pumpAndSettle();

      expect(answer, isNotNull);
      expect(answer!.choice, StillGoing.stopNow);
      // Untouched, the wheel sits at now.
      expect(answer!.endedAt, now);
    });
  });
}

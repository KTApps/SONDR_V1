import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/core/utils/figma_scale.dart';
import 'package:sondr/features/habits/habits_providers.dart';
import 'package:sondr/features/habits/habits_screen.dart';
import 'package:sondr/features/habits/models/daily_habits.dart';
import 'package:sondr/shared/blur_sheet.dart';

/// A question over the app wears the Habits page's clothes.
///
/// Not approximately: the two are pumped side by side at each text size
/// and the numbers are compared. If the Habits page moves, this fails —
/// which is the point of measuring it rather than copying it.
const double w13 = 390;
const double h13 = 844;

void main() {
  void iPhone13Pro(WidgetTester tester) {
    tester.view.physicalSize = const Size(w13 * 3, h13 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
  }

  /// The Habits page, with three habits so one sits in the middle.
  Future<void> pumpHabits(WidgetTester tester, double ts) async {
    iPhone13Pro(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayHabitsProvider.overrideWithValue(
            const DailyHabits(dayKey: '2026-10-24', ticks: [
              HabitTick(habitId: 'a', name: 'One', done: true),
              // Done, so its tone is the ordinary one an answer uses;
              // the not-done grey is compared in its own test below.
              HabitTick(habitId: 'b', name: 'Two', done: true),
              HabitTick(habitId: 'c', name: 'Three', done: true),
            ]),
          ),
          habitStreakForProvider.overrideWith((ref, id) => 0),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          // ABOVE the navigator, which is where a device's own setting
          // sits — a route pushed over this inherits it, and one wrapped
          // below it would not.
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(ts)),
            child: child!,
          ),
          home: const HabitsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The sheet, with the same three labels.
  Future<void> pumpSheet(
    WidgetTester tester,
    double ts, {
    BlurView Function(BlurSheetHandle)? view,
    List<String> labels = const ['One', 'Two', 'Three'],
  }) async {
    iPhone13Pro(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(ts)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showBlurSheet(
                  context,
                  view ??
                      (h) => BlurView(
                            items: [
                              for (final l in labels)
                                BlurItem(label: l, onTap: () {}),
                            ],
                          ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  TextStyle styleOf(WidgetTester tester, String text) {
    final p = tester.renderObject<RenderParagraph>(find.text(text));
    TextStyle? found;
    p.text.visitChildren((s) {
      if (s is TextSpan && s.text == text) found = s.style;
      return true;
    });
    return found ?? p.text.style!;
  }

  group('an answer is a habit name', () {
    for (final ts in [0.824, 1.0, 1.235]) {
      testWidgets('same type, same place, at $ts', (tester) async {
        await pumpHabits(tester, ts);
        final habitMiddle = tester.getRect(find.text('Two'));
        final habitFirst = tester.getRect(find.text('One'));
        final habitStyle = styleOf(tester, 'Two');
        final habitTitle = tester.getRect(find.textContaining(RegExp(
            r'^(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday)$')));
        final habitAdd = tester.getRect(find.text('Add habit'));

        await pumpSheet(tester, ts);
        final sheetMiddle = tester.getRect(find.text('Two'));
        final sheetFirst = tester.getRect(find.text('One'));
        final sheetStyle = styleOf(tester, 'Two');
        final sheetCancel = tester.getRect(find.text('Back'));

        // The type.
        expect(sheetStyle.fontSize, closeTo(habitStyle.fontSize!, 0.01));
        expect(sheetStyle.fontWeight, habitStyle.fontWeight);
        expect(sheetStyle.color, habitStyle.color);

        // The place: the middle item, and the gap to the one above it.
        expect(sheetMiddle.center.dy, closeTo(habitMiddle.center.dy, 0.5));
        expect(sheetMiddle.top, closeTo(habitMiddle.top, 0.5));
        expect(
          sheetMiddle.top - sheetFirst.bottom,
          closeTo(habitMiddle.top - habitFirst.bottom, 0.5),
        );
        // Centred where the habit is. The label itself is now only as wide
        // as its word (the word is the tap target), so the centre is the
        // comparison, not the edges of a full-width box.
        expect(sheetMiddle.center.dx, closeTo(habitMiddle.center.dx, 0.5));

        // Back stands where "Add habit" does.
        expect(sheetCancel.top, closeTo(habitAdd.top, 0.5));
        expect(sheetCancel.center.dy, closeTo(habitAdd.center.dy, 0.5));
        expect(sheetCancel.height, closeTo(habitAdd.height, 0.5));

        // And a title, where the weekday is.
        await pumpSheet(
          tester,
          ts,
          view: (h) => const BlurView(title: 'Title', items: []),
        );
        final sheetTitle = tester.getRect(find.text('Title'));
        expect(sheetTitle.top, closeTo(habitTitle.top, 0.5));
        expect(sheetTitle.height, closeTo(habitTitle.height, 0.5));
        expect(styleOf(tester, 'Title').fontSize, kBlurTitleSize);
      });
    }

    testWidgets('the quiet tone is the not-done grey', (tester) async {
      await pumpSheet(
        tester,
        1.0,
        view: (h) => BlurView(items: [
          BlurItem(label: 'Ordinary', onTap: () {}),
          BlurItem(label: 'Quiet', quiet: true, onTap: () {}),
        ]),
      );
      final context = tester.element(find.byType(BlurSheet));
      final tokens = GreyscaleTokens.of(context);
      expect(styleOf(tester, 'Ordinary').color, tokens.textPrimary);
      expect(styleOf(tester, 'Quiet').color, tokens.textTertiary);
      expect(tokens.textPrimary, const Color(0xFFFAFAFA));
      expect(tokens.textTertiary, const Color(0xFF6E6E6E));
    });
  });

  group('the blur itself', () {
    testWidgets('is the same filter and scrim Habits uses', (tester) async {
      await pumpHabits(tester, 1.0);
      final habitBlur = tester.widget<BackdropFilter>(
        find.byType(BackdropFilter).first,
      );
      final habitScrim = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(BackdropFilter),
          matching: find.byType(ColoredBox),
        ).first,
      );

      await pumpSheet(tester, 1.0);
      final sheetBlur = tester.widget<BackdropFilter>(
        find.byType(BackdropFilter).first,
      );
      final sheetScrim = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(BackdropFilter),
          matching: find.byType(ColoredBox),
        ).first,
      );

      expect(sheetBlur.filter.toString(), habitBlur.filter.toString());
      expect(sheetScrim.color, habitScrim.color);
      expect(
        sheetBlur.filter.toString(),
        ImageFilter.blur(sigmaX: kBlurSigma, sigmaY: kBlurSigma).toString(),
      );
    });

    testWidgets('one blur, never two, however many views deep', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        1.0,
        view: (h) => BlurView(items: [
          BlurItem(
            label: 'Onward',
            onTap: () => h.show(
              BlurView(items: [BlurItem(label: 'Deeper', onTap: () {})]),
            ),
          ),
        ]),
      );
      expect(find.byType(BackdropFilter), findsOneWidget);
      await tester.tap(find.text('Onward'));
      await tester.pumpAndSettle();
      expect(find.text('Deeper'), findsOneWidget);
      expect(find.text('Onward'), findsNothing);
      expect(
        find.byType(BackdropFilter),
        findsOneWidget,
        reason: 'a second blur was stacked over the first',
      );
      // And still one route: the view changed in place.
      expect(find.byType(BlurSheet), findsOneWidget);
    });
  });

  group('getting out', () {
    testWidgets('a tap on the blur closes it', (tester) async {
      await pumpSheet(tester, 1.0);
      await tester.tapAt(const Offset(w13 / 2, 40));
      await tester.pumpAndSettle();
      expect(find.byType(BlurSheet), findsNothing);
    });

    testWidgets('Cancel closes it', (tester) async {
      await pumpSheet(tester, 1.0);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(BlurSheet), findsNothing);
    });

    testWidgets('a downward swipe closes it', (tester) async {
      await pumpSheet(tester, 1.0);
      await tester.drag(find.byType(BlurSheet), const Offset(0, 120));
      await tester.pumpAndSettle();
      expect(find.byType(BlurSheet), findsNothing);
    });

    testWidgets('an answer does its work and the sheet can close', (
      tester,
    ) async {
      var tapped = 0;
      await pumpSheet(
        tester,
        1.0,
        view: (h) => BlurView(items: [
          BlurItem(
            label: 'Do it',
            onTap: () {
              tapped++;
              h.close();
            },
          ),
        ]),
      );
      await tester.tap(find.text('Do it'));
      await tester.pumpAndSettle();
      expect(tapped, 1);
      expect(find.byType(BlurSheet), findsNothing);
    });
  });

  group('the longest things it has to say', () {
    for (final label in ['Nudity or sexual content', 'Delete account']) {
      testWidgets('"$label" at 1.235', (tester) async {
        await pumpSheet(tester, 1.235, labels: [label]);
        expect(tester.takeException(), isNull);
        final box = tester.getRect(find.text(label));
        final context = tester.element(find.byType(BlurSheet));
        final scale = figmaScale(context);
        // Inside the gutter, whatever it takes to get there.
        expect(box.left, greaterThanOrEqualTo(kBlurSideInset * scale - 0.5));
        expect(box.right, lessThanOrEqualTo(w13 - kBlurSideInset * scale + 0.5));
      });
    }
  });

  group('a title with something to explain', () {
    testWidgets('the line sits a base under it, in the quiet tone', (
      tester,
    ) async {
      await pumpSheet(
        tester,
        1.0,
        view: (h) => const BlurView(
          title: 'Delete your account?',
          explanation: 'This cannot be undone.',
        ),
      );
      final title = tester.getRect(find.text('Delete your account?'));
      final line = tester.getRect(find.text('This cannot be undone.'));
      final context = tester.element(find.byType(BlurSheet));
      final scale = figmaScale(context);
      expect(line.top - title.bottom, closeTo(kBlurExplanationGap * scale, 0.5));
      expect(
        styleOf(tester, 'This cannot be undone.').color,
        GreyscaleTokens.of(context).textTertiary,
      );
      expect(
        styleOf(tester, 'This cannot be undone.').fontSize,
        closeTo(kBlurExplanationSize * scale, 0.01),
      );
    });
  });
}

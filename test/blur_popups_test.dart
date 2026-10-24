import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/shared/blur_sheet.dart';
import 'package:sondr/shared/sondr_prompt.dart';

/// Every confirm and every choice in the app is that one frosted view
/// now, and still answers exactly as it did.
///
/// The components are shared, so this tests them once rather than seven
/// times over: what each caller passes is its own business, and its own
/// tests already pin that.
void main() {
  Future<T?> run<T>(
    WidgetTester tester,
    Future<T> Function(BuildContext) open,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    T? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () async => result = await open(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return result;
  }

  group('a confirm', () {
    Future<bool?> confirm(WidgetTester tester) => run<bool>(
      tester,
      (context) => showSondrConfirm(
        context,
        title: 'Delete your account?',
        body: "This can't be undone.",
        confirmLabel: 'Delete account',
      ),
    );

    testWidgets('is the frosted view, question and all', (tester) async {
      await confirm(tester);
      expect(find.byType(BlurSheet), findsOneWidget);
      expect(find.text('Delete your account?'), findsOneWidget);
      expect(find.text("This can't be undone."), findsOneWidget);
      expect(find.text('Delete account'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('the answer is a yes', (tester) async {
      await confirm(tester);
      await tester.tap(find.text('Delete account'));
      await tester.pumpAndSettle();
      expect(find.byType(BlurSheet), findsNothing);
    });

    testWidgets('Cancel, a tap on the blur and a swipe are all a no', (
      tester,
    ) async {
      for (final dismiss in [
        (WidgetTester t) async => t.tap(find.text('Cancel')),
        (WidgetTester t) async => t.tapAt(const Offset(195, 40)),
        (WidgetTester t) async =>
            t.drag(find.byType(BlurSheet), const Offset(0, 120)),
      ]) {
        await confirm(tester);
        await dismiss(tester);
        await tester.pumpAndSettle();
        expect(find.byType(BlurSheet), findsNothing);
      }
    });

    testWidgets('the destructive answer is nowhere near the exit', (
      tester,
    ) async {
      await confirm(tester);
      final answer = tester.getRect(find.text('Delete account'));
      final cancel = tester.getRect(find.text('Cancel'));
      // Home's two lines apart: the answer sits in the middle of the
      // screen and the way out is at the bottom, where Add habit is.
      expect(cancel.top - answer.bottom, greaterThan(200));
    });
  });

  group('a choice', () {
    testWidgets('each answer returns its own value', (tester) async {
      for (final want in ['one', 'two']) {
        final got = await run<String?>(
          tester,
          (context) => showSondrChoice<String>(
            context,
            choices: const [
              (label: 'One', value: 'one'),
              (label: 'Two', value: 'two'),
            ],
          ),
        );
        expect(got, isNull, reason: 'nothing tapped yet');
        await tester.tap(find.text(want == 'one' ? 'One' : 'Two'));
        await tester.pumpAndSettle();
        expect(find.byType(BlurSheet), findsNothing);
      }
    });

    testWidgets('a title and a line, where a confirm puts them', (
      tester,
    ) async {
      await run<String?>(
        tester,
        (context) => showSondrChoice<String>(
          context,
          title: 'Why are you reporting this?',
          choices: const [(label: 'Spam', value: 'spam')],
        ),
      );
      final title = tester.getRect(find.text('Why are you reporting this?'));
      final item = tester.getRect(find.text('Spam'));
      expect(title.top, lessThan(item.top));
      expect(title.top, closeTo(kBlurTitleTop * 0.9906, 0.5));
    });

    testWidgets('quiet values wear the not-done grey', (tester) async {
      await run<String?>(
        tester,
        (context) => showSondrChoice<String>(
          context,
          choices: const [
            (label: 'Support', value: 'support'),
            (label: 'Sign out', value: 'signOut'),
          ],
          quiet: {'signOut'},
        ),
      );
      expect(
        tester.widget<Text>(find.text('Sign out')).style!.color,
        const Color(0xFF6E6E6E),
      );
      expect(
        tester.widget<Text>(find.text('Support')).style!.color,
        const Color(0xFFFAFAFA),
      );
    });
  });

  group('what was not converted', () {
    testWidgets('a text prompt is still its own card', (tester) async {
      await run<String?>(
        tester,
        (context) => showSondrPrompt(
          context,
          title: 'New task',
          confirmLabel: 'Add',
        ),
      );
      // Creation prompts keep the card and the keyboard-hugging layout.
      expect(find.byType(BlurSheet), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('New task'), findsOneWidget);
    });
  });
}

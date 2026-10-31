import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/core/utils/figma_scale.dart';
import 'package:sondr/features/auth/delete_account.dart';
import 'package:sondr/shared/blur_sheet.dart';
import 'package:sondr/shared/sondr_field.dart';
import 'package:sondr/shared/sondr_prompt.dart';

/// The deletion's password step.
///
/// Everything on it stands where it stands. The keyboard opening covers
/// the way out and moves nothing; a line about a wrong password appears
/// between the field and the answer and moves nothing either. The
/// answer is a word, grey until there is enough of a password to be one.
void main() {
  const w = 390.0, h = 844.0;
  const keyboard = 336.0;
  const accessoryBar = 44.0;

  /// The step, opened over nothing, with [onSubmit] standing in for the
  /// re-authentication.
  Future<void> open(
    WidgetTester tester, {
    double textScale = 1.0,
    double viewInset = 0,
    Future<String?> Function(String)? onSubmit,
  }) async {
    tester.view.physicalSize = const Size(w * 3, h * 3);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
    if (viewInset > 0) tester.view.viewInsets = FakeViewPadding(bottom: viewInset * 3);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Builder(
            builder: (c) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => showBlurPasswordStep(
                    c,
                    title: kPasswordPrompt,
                    confirmLabel: kDeleteAccountConfirm,
                    busyLabel: kDeleteAccountWorking,
                    onSubmit: onSubmit ?? (_) async => null,
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
  }

  Rect rectOf(WidgetTester tester, Finder f) => tester.getRect(f);
  Finder title() => find.text(kPasswordPrompt);
  Finder field() => find.byType(TextField);
  Finder answer() => find.text(kDeleteAccountConfirm);

  group('where everything stands', () {
    testWidgets('the title keeps its place, the field sits under it at Add friends\' own gap', (tester) async {
      await open(tester);
      final scale = figmaScale(tester.element(title()));
      final t = rectOf(tester, title());
      final f = rectOf(tester, field());
      expect(t.top, closeTo(kBlurTitleTop * scale, 0.5));
      expect(t.center.dy, closeTo(117, 1), reason: 'where it has always been');
      // Add friends puts 24 between its heading and its field.
      expect(f.top - t.bottom, closeTo(kBlurPasswordFieldGap * scale, 0.5));
      expect(kBlurPasswordFieldGap, 24);
    });

    testWidgets('the answer keeps the place the centred list gave it, and Back is where it was', (tester) async {
      await open(tester);
      expect(rectOf(tester, answer()).center.dy, closeTo(439.43, 1));
      expect(rectOf(tester, find.text('Back')).top, closeTo(725.13, 1));
    });

    testWidgets('the keyboard opening moves nothing; it only covers Back', (tester) async {
      await open(tester);
      List<Rect> everything() => [
        rectOf(tester, title()),
        rectOf(tester, field()),
        rectOf(tester, answer()),
        rectOf(tester, find.text('Back')),
      ];
      final before = everything();
      // The keyboard comes up over the step that is already open.
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 3);
      await tester.pumpAndSettle();
      final after = everything();
      expect(after, before, reason: 'not one of them moved');
      // Back is under the keyboard, which is the only change there is.
      expect(after.last.top, greaterThan(h - keyboard));
      // And putting it away changes nothing back, because nothing moved.
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(everything(), before);
    });

    testWidgets('an error appears between the field and the answer, and moves neither', (tester) async {
      await open(tester, onSubmit: (_) async => kWrongPassword);
      final before = [rectOf(tester, title()), rectOf(tester, field()), rectOf(tester, answer())];
      await type(tester, 'wrongun');
      await tester.tap(answer());
      await tester.pumpAndSettle();

      expect(find.text(kWrongPassword), findsOneWidget);
      final after = [rectOf(tester, title()), rectOf(tester, field()), rectOf(tester, answer())];
      expect(after, before, reason: 'the line was already a space; nothing moved into it');

      final line = rectOf(tester, find.text(kWrongPassword));
      final scale = figmaScale(tester.element(title()));
      final f = rectOf(tester, field());
      expect(line.top - (f.top + SondrField.lineHeightOf(tester.element(field()))),
          closeTo(kBlurPasswordErrorGap * scale, 0.5));
      expect(line.bottom, lessThan(rectOf(tester, answer()).top));
      expect(line.center.dx, closeTo(w / 2, 1), reason: 'centred');
      // The app's one error style.
      final style = tester.widget<Text>(find.text(kWrongPassword)).style!;
      expect(style.fontWeight, FontWeight.w700);
      expect(style.color, GreyscaleTokens.dark.textPrimary);
      expect(style.fontSize, closeTo(13 * scale, 0.01));
    });

    for (final ts in [0.824, 1.0, 1.235]) {
      testWidgets('at textScaler $ts the answer still clears a keyboard and its bar', (tester) async {
        await open(tester, textScale: ts, viewInset: keyboard);
        final a = rectOf(tester, answer());
        expect(a.bottom, lessThan(h - keyboard - accessoryBar),
            reason: 'the answer must be reachable with the keyboard up');
        // And it is still on its line, whatever its own height.
        final scale = figmaScale(tester.element(title()));
        expect(a.center.dy, closeTo(kBlurPasswordActionCentre * scale, 1));
      });
    }
  });

  group('how it behaves', () {
    testWidgets('no keyboard until the field is tapped', (tester) async {
      await open(tester);
      expect(tester.widget<TextField>(field()).autofocus, isFalse);
      final focus = tester.widget<TextField>(field()).focusNode;
      expect(focus?.hasFocus ?? false, isFalse);
    });

    testWidgets('the answer is grey and inert under six characters, and white at six', (tester) async {
      var submits = 0;
      await open(tester, onSubmit: (_) async {
        submits++;
        return null;
      });
      Color? tone() => tester.widget<Text>(answer()).style?.color;

      expect(tone(), GreyscaleTokens.dark.textTertiary);
      await type(tester, 'hunte');
      expect(tone(), GreyscaleTokens.dark.textTertiary, reason: 'five is not enough');
      await tester.tap(answer());
      await tester.pumpAndSettle();
      expect(submits, 0, reason: 'a tap on the grey word does nothing');

      await type(tester, 'hunter');
      expect(tone(), GreyscaleTokens.dark.textPrimary, reason: 'six is');
      expect(kPasswordMinLength, 6);
      await tester.tap(answer());
      await tester.pumpAndSettle();
      expect(submits, 1);
    });

    testWidgets('Return puts the keyboard away and submits nothing', (tester) async {
      var submits = 0;
      await open(tester, onSubmit: (_) async {
        submits++;
        return null;
      });
      await tester.tap(field());
      await tester.pumpAndSettle();
      await type(tester, 'hunter22');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(submits, 0, reason: 'the answer is a word on the screen, and it is tapped');
      expect(tester.testTextInput.isVisible, isFalse);
      // Still on the step, with what was typed.
      expect(find.text(kPasswordPrompt), findsOneWidget);
      expect(tester.widget<TextField>(field()).controller?.text, 'hunter22');
    });

    testWidgets('while it works the answer says so, in place', (tester) async {
      final gate = Completer<String?>();
      await open(tester, onSubmit: (_) => gate.future);
      await type(tester, 'hunter22');
      final before = rectOf(tester, answer());
      await tester.tap(answer());
      await tester.pump();

      expect(find.text(kDeleteAccountWorking), findsOneWidget);
      expect(find.text(kDeleteAccountConfirm), findsNothing);
      expect(rectOf(tester, find.text(kDeleteAccountWorking)).center.dy,
          closeTo(before.center.dy, 0.5), reason: 'no jump');
      gate.complete(kWrongPassword);
      await tester.pumpAndSettle();
      expect(find.text(kDeleteAccountConfirm), findsOneWidget);
    });

    testWidgets('the line clears on the next keystroke', (tester) async {
      await open(tester, onSubmit: (_) async => kWrongPassword);
      await type(tester, 'wrongun');
      await tester.tap(answer());
      await tester.pumpAndSettle();
      expect(find.text(kWrongPassword), findsOneWidget);
      await type(tester, 'wrongun2');
      expect(find.text(kWrongPassword), findsNothing);
    });

    testWidgets('the password is obscured, uncapitalised and uncorrected', (tester) async {
      await open(tester);
      final f = tester.widget<TextField>(field());
      expect(f.obscureText, isTrue);
      expect(f.autocorrect, isFalse);
      expect(f.textCapitalization, TextCapitalization.none);
    });
  });
}

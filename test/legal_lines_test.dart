import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/features/auth/account_screen.dart';
import 'package:sondr/features/auth/apple_sign_in_button.dart';
import 'package:sondr/features/auth/auth_repository.dart';
import 'package:sondr/features/auth/auth_screen.dart';
import 'package:sondr/features/auth/legal_lines.dart';
import 'package:sondr/shared/legal.dart';

import 'support/app_viewport.dart';

/// The terms line, and the support links.
///
/// Two App Store requirements, both of them words rather than screens: an
/// account cannot be created without saying what it agrees to, and the
/// privacy policy, terms and a support contact have to be reachable from
/// inside the app.
///
/// What is pinned here is the thing that could quietly break: the sentence
/// was added UNDER everything on the account-creation landing so that it
/// moved nothing, and the support links have to sit on ONE line beside Sign
/// out at every text size a release build can be set to.

/// Where each page actually opens, recorded instead of launched — url_launcher
/// is a plugin, and there is nothing on the other end of it in a test.
class _RecordingPages implements LegalPages {
  final List<String> opened = [];

  @override
  Future<void> open(String url) async => opened.add(url);
}

class _Auth implements AuthRepository {
  _Auth(this.user);

  final User? user;

  @override
  User? get currentUser => user;

  @override
  bool get isAnonymous => user?.isAnonymous ?? true;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  late _RecordingPages pages;

  setUp(() => pages = _RecordingPages());

  /// The account block at the reference canvas, inside the profile page's own
  /// 24 gutter — which is what sets the width the links have to fit inside.
  Future<void> pump(
    WidgetTester tester, {
    double textScale = 1.0,
    User? user,
  }) async {
    useReferenceViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(_Auth(user)),
          legalPagesProvider.overrideWithValue(pages),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(kRefWidth, kRefHeight),
              textScaler: TextScaler.linear(textScale),
            ),
            child: const Scaffold(
              body: Padding(
                padding: EdgeInsets.symmetric(horizontal: 24),
                child: AccountBody(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The content width the block gets: the canvas less the page's two gutters.
  const double contentWidth = kRefWidth - 48;
  const double contentRight = 24 + contentWidth;


  /// The sentence's own paragraph.
  RenderParagraph sentence(WidgetTester tester) =>
      tester.renderObject<RenderParagraph>(
        find.textContaining(TermsNotice.lead),
      );

  /// The type the paragraph actually renders: the style the sentence's words
  /// resolve to, the style each linked phrase resolves to, and how many
  /// placeholders (WidgetSpans) are in there.
  ({TextStyle sentence, List<TextStyle> links, int placeholders}) typeOf(
    WidgetTester tester,
  ) {
    TextStyle? plain;
    final links = <TextStyle>[];
    var placeholders = 0;
    void walk(InlineSpan span, TextStyle? inherited) {
      if (span is! TextSpan) {
        placeholders++;
        return;
      }
      final here = span.style ?? inherited;
      if (span.text == TermsNotice.lead) plain = here;
      if (span.text == TermsNotice.terms ||
          span.text == TermsNotice.privacy) {
        links.add(here!);
      }
      for (final kid in span.children ?? const <InlineSpan>[]) {
        walk(kid, here);
      }
    }
    walk(sentence(tester).text, null);
    expect(plain, isNotNull, reason: 'the sentence was not found');
    expect(links.length, 2, reason: 'both phrases were not found');
    return (sentence: plain!, links: links, placeholders: placeholders);
  }

  /// The box the paragraph gives a phrase, as painted.
  Size inkOf(WidgetTester tester, String phrase) {
    final p = sentence(tester);
    final i = p.text.toPlainText().indexOf(phrase);
    expect(i, isNot(-1), reason: phrase);
    final boxes = p.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + phrase.length),
    );
    final rects = [for (final b in boxes) b.toRect()];
    return Size(
      rects.fold(0.0, (sum, r) => sum + r.width),
      rects.map((r) => r.height).reduce((a, b) => a > b ? a : b),
    );
  }

  /// What that phrase measures at the sentence's own style, scaled once.
  double paintedWidth(WidgetTester tester, String phrase, TextStyle style) {
    final context = tester.element(find.byType(TermsNotice));
    final painter = TextPainter(
      text: TextSpan(text: phrase, style: style),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return painter.width;
  }

  group('the terms line', () {
    testWidgets('says what creating an account agrees to', (tester) async {
      await pump(tester);
      expect(find.byType(TermsNotice), findsOneWidget);
      expect(
        sentence(tester).text.toPlainText(),
        'By creating an account, you agree to the terms and privacy '
            'policy.',
      );
    });

    testWidgets('12pt tertiary, with the two linked phrases a step brighter', (
      tester,
    ) async {
      await pump(tester);
      final context = tester.element(find.byType(TermsNotice));
      final tokens = GreyscaleTokens.of(context);
      final type = typeOf(tester);

      expect(type.sentence.fontSize, 12);
      expect(type.sentence.color, tokens.textTertiary);
      expect(tokens.textTertiary, const Color(0xFF6E6E6E));
      for (final link in type.links) {
        expect(link.color, tokens.textSecondary);
        // Tone alone says tappable — no underline, and no colour anywhere.
        expect(link.decoration, isNot(TextDecoration.underline));
      }
      expect(tokens.textSecondary, const Color(0xFFB0B0B0));
    });

    /// The bug this group exists for.
    ///
    /// The linked phrases used to be WidgetSpans. The framework scales a
    /// WidgetSpan's child by the text scale factor, and the Text inside it
    /// applies the same MediaQuery scale again — so the words rendered at
    /// 12 x scale^2: right at the default size, 18% small at 0.824 and 24%
    /// large at 1.235. They are plain spans of the one paragraph now, which
    /// is the only arrangement that cannot drift.
    for (final ts in [0.824, 1.0, 1.235]) {
      testWidgets('one run of type, differing only in colour, at $ts', (
        tester,
      ) async {
        await pump(tester, textScale: ts);
        final type = typeOf(tester);

        // Nothing in the paragraph is a placeholder.
        expect(type.placeholders, 0, reason: 'a WidgetSpan is back');

        // Every declared field matches the sentence except the colour.
        for (final link in type.links) {
          expect(
            link.copyWith(color: type.sentence.color),
            type.sentence,
            reason: 'a link differs from the sentence by more than colour',
          );
        }

        // And as RENDERED: one line box for the whole sentence, and each
        // phrase the width one scaling gives it.
        final boxes = {
          for (final phrase in ['account,', TermsNotice.terms, TermsNotice.privacy])
            phrase: inkOf(tester, phrase),
        };
        final heights = {for (final b in boxes.values) b.height}.toList();
        expect(
          heights.reduce((a, b) => (a - b).abs() < 0.01 ? a : -1),
          greaterThan(0),
          reason: 'the phrases sit on different line boxes: $boxes',
        );
        for (final phrase in [TermsNotice.terms, TermsNotice.privacy]) {
          final painted = paintedWidth(tester, phrase, type.sentence);
          // 2%: the bug being guarded against was 18% small at 0.824 and
          // 24% large at 1.235, and a phrase that wraps onto the second
          // line measures a fraction of a point narrower than the painter
          // gives it standing alone.
          expect(
            boxes[phrase]!.width,
            closeTo(painted, painted * 0.02),
            reason: '$phrase is not the size the sentence is',
          );
        }
      });
    }

    testWidgets('each phrase opens its own page', (tester) async {
      await pump(tester);

      // Tapped as words inside the sentence, which is what they now are.
      await tester.tapOnText(
        find.textRange.ofSubstring(TermsNotice.terms),
      );
      await tester.pump();
      expect(pages.opened, ['https://s-ndr.com/terms']);

      await tester.tapOnText(
        find.textRange.ofSubstring(TermsNotice.privacy),
      );
      await tester.pump();
      expect(pages.opened, [
        'https://s-ndr.com/terms',
        'https://s-ndr.com/privacy',
      ]);
    });

    /// Measured on the tree BEFORE the sentence existed, at each text size.
    /// The sentence is the last thing in the column, under the Apple button,
    /// so none of these could move — and if one ever does, this is what says
    /// so rather than a device screenshot.
    const before = [
      (ts: 0.824, title: 0.0, warning: 21.0, create: 60.0, signIn: 101.0,
          appleTop: 142.0, appleBottom: 186.0),
      (ts: 1.0, title: 0.0, warning: 24.0, create: 66.0, signIn: 111.0,
          appleTop: 156.0, appleBottom: 200.0),
      (ts: 1.235, title: 0.0, warning: 28.0, create: 74.0, signIn: 124.0,
          appleTop: 174.0, appleBottom: 218.0),
    ];

    for (final was in before) {
      final ts = was.ts;
      testWidgets('nothing above it moved at $ts', (tester) async {
        await pump(tester, textScale: ts);

        double top(Finder f) => tester.getRect(f).top;
        expect(top(find.text('Guest account')), closeTo(was.title, 0.5));
        expect(
          top(find.textContaining('progress is lost')),
          closeTo(was.warning, 0.5),
        );
        expect(top(find.text('Create account')), closeTo(was.create, 0.5));
        expect(
          top(find.text('I already have an account')),
          closeTo(was.signIn, 0.5),
        );
        final apple = tester.getRect(find.byType(AppleSignInButton));
        expect(apple.top, closeTo(was.appleTop, 0.5));
        expect(apple.bottom, closeTo(was.appleBottom, 0.5));

        // And the sentence is below all of it, inside the gutter.
        final notice = tester.getRect(find.byType(TermsNotice));
        expect(notice.top, greaterThanOrEqualTo(apple.bottom));
        expect(notice.left, closeTo(24, 0.5));
        expect(notice.right, closeTo(contentRight, 0.5));
      });
    }

    testWidgets('not on the sign-in screen', (tester) async {
      useReferenceViewport(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [legalPagesProvider.overrideWithValue(pages)],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const AuthScreen(startInSignUp: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(TermsNotice), findsNothing);
    });
  });

}

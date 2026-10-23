import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/debug_flags.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/features/auth/account_screen.dart';
import 'package:sondr/features/auth/apple_sign_in_button.dart';
import 'package:sondr/features/auth/auth_repository.dart';
import 'package:sondr/features/auth/auth_screen.dart';
import 'package:sondr/features/auth/legal_lines.dart';
import 'package:sondr/features/auth/sign_out_action.dart';
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

/// A permanent account, which is what puts Sign out and the support links on
/// the screen. Only the two fields the view reads are real.
class _Account implements User {
  @override
  bool get isAnonymous => false;

  @override
  String? get email => 'tanaka@example.com';

  @override
  String get uid => 'me';

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

  group('the terms line', () {
    testWidgets('says what creating an account agrees to', (tester) async {
      await pump(tester);
      expect(find.byType(TermsNotice), findsOneWidget);
      expect(
        find.textContaining('By creating an account, you agree to the'),
        findsOneWidget,
      );
      expect(find.text('terms'), findsOneWidget);
      expect(find.text('privacy policy'), findsOneWidget);
    });

    testWidgets('12pt tertiary, with the two linked phrases a step brighter', (
      tester,
    ) async {
      await pump(tester);
      final context = tester.element(find.byType(TermsNotice));
      final tokens = GreyscaleTokens.of(context);

      final sentence = tester.widget<Text>(
        find.textContaining('By creating an account'),
      );
      final base = sentence.textSpan!.style!;
      expect(base.fontSize, 12);
      expect(base.color, tokens.textTertiary);
      expect(tokens.textTertiary, const Color(0xFF6E6E6E));

      for (final word in ['terms', 'privacy policy']) {
        final link = tester.widget<Text>(find.text(word));
        expect(link.style!.fontSize, 12, reason: word);
        expect(link.style!.color, tokens.textSecondary, reason: word);
        // Tone alone says tappable — no underline, and no colour anywhere.
        expect(link.style!.decoration, isNot(TextDecoration.underline));
      }
      expect(tokens.textSecondary, const Color(0xFFB0B0B0));
    });

    testWidgets('each phrase opens its own page', (tester) async {
      await pump(tester);

      await tester.tap(find.text('terms'));
      await tester.pump();
      expect(pages.opened, ['https://s-ndr.com/terms']);

      await tester.tap(find.text('privacy policy'));
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

  group('the support links', () {
    testWidgets('three words beside Sign out, each opening its page', (
      tester,
    ) async {
      await pump(tester, user: _Account());
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.byType(SupportLinks), findsOneWidget);

      for (final (label, url) in [
        ('Support', 'https://s-ndr.com/support'),
        ('Privacy', 'https://s-ndr.com/privacy'),
        ('Terms', 'https://s-ndr.com/terms'),
      ]) {
        expect(find.text(label), findsOneWidget);
        await tester.tap(find.text(label));
        await tester.pump();
        expect(pages.opened.last, url, reason: label);
      }
      expect(pages.opened.length, 3);
    });

    testWidgets('plain grey, not actions', (tester) async {
      await pump(tester, user: _Account());
      final context = tester.element(find.byType(SupportLinks));
      final tokens = GreyscaleTokens.of(context);
      for (final label in ['Support', 'Privacy', 'Terms']) {
        final word = tester.widget<Text>(find.text(label));
        expect(word.style!.fontSize, SupportLinks.fontSize, reason: label);
        expect(word.style!.fontWeight, FontWeight.w400, reason: label);
        expect(word.style!.color, tokens.textSecondary, reason: label);
      }
    });

    for (final ts in [0.824, 1.0, 1.235]) {
      testWidgets('fit beside Sign out, one line, at $ts', (tester) async {
        await pump(tester, textScale: ts, user: _Account());

        final links = tester.getRect(find.byType(SupportLinks));
        final signOut = tester.getRect(find.byType(SignOutAction));

        // Inside the gutter, never over the edge — a Row would have painted
        // the overflow stripes instead of failing.
        expect(tester.takeException(), isNull);
        expect(links.right, lessThanOrEqualTo(contentRight + 0.5));
        expect(links.left, greaterThanOrEqualTo(23.5));

        // The three words are on one line as each other, always.
        final tops = ['Support', 'Privacy', 'Terms']
            .map((l) => tester.getRect(find.text(l)).top)
            .toSet();
        expect(tops.length, 1, reason: 'the words broke across lines');

        if (!kDebugTools) {
          // The release build: beside Sign out, sharing its line.
          expect(
            links.center.dy,
            closeTo(signOut.center.dy, 1),
            reason: 'the links fell below Sign out at $ts',
          );
          expect(links.left, greaterThan(signOut.right - 0.5));
        } else {
          // A DEBUG_TOOLS build adds "Debug" to the line, which at 1.0 is 25
          // too wide. The links drop to their own line rather than overflow.
          expect(links.top, greaterThanOrEqualTo(signOut.top - 0.5));
        }
      });
    }
  });
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/debug_flags.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/features/auth/account_screen.dart';
import 'package:sondr/features/auth/auth_repository.dart';
import 'package:sondr/features/auth/delete_account.dart';
import 'package:sondr/features/auth/legal_lines.dart';
import 'package:sondr/features/auth/more_sheet.dart';
import 'package:sondr/features/debug/debug_panel.dart';
import 'package:sondr/shared/legal.dart';
import 'package:sondr/shared/sondr_action.dart';

import 'support/app_viewport.dart';

/// The account block's one word, and what is behind it.
///
/// Sign out, the three pages and Debug all used to stand in the block. Five
/// words in a row needed 372 of the 345 that block has at the default text
/// size — and "Delete account" was the sixth being asked for. So the block
/// carries one word and the sheet carries the rest.

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

  Future<void> openSheet(WidgetTester tester) async {
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
  }

  /// Every label on the card, top to bottom.
  List<String> sheetLabels(WidgetTester tester) {
    final card = find
        .ancestor(of: find.text('Support'), matching: find.byType(Material))
        .last;
    final labels = find.descendant(of: card, matching: find.byType(Text));
    return [
      for (final element in labels.evaluate()) (element.widget as Text).data!,
    ];
  }

  group('the account block', () {
    testWidgets('signed in: Signed in, the email, and one word', (
      tester,
    ) async {
      await pump(tester, user: _Account());
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text('tanaka@example.com'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      // Everything that used to stand here is behind the word now.
      for (final gone in ['Sign out', 'Support', 'Privacy', 'Terms']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
    });

    testWidgets('More is Sign out\'s style: supporting, not an emphasis', (
      tester,
    ) async {
      await pump(tester, user: _Account());
      final more = tester.widget<SondrAction>(
        find.ancestor(
          of: find.text('More'),
          matching: find.byType(SondrAction),
        ),
      );
      expect(more.supporting, isTrue);
      final word = tester.widget<Text>(find.text('More'));
      final tokens = GreyscaleTokens.of(
        tester.element(find.byType(AccountBody)),
      );
      expect(word.style!.color, tokens.textSecondary);
      expect(word.style!.fontSize, 15);
    });

    testWidgets('a guest keeps every row they had, and gains the word', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text('Guest account'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.text('I already have an account'), findsOneWidget);
      expect(find.byType(TermsNotice), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      // Below the sentence, so nothing above it moved.
      expect(
        tester.getRect(find.text('More')).top,
        greaterThan(tester.getRect(find.byType(TermsNotice)).bottom),
      );
    });
  });

  group('the sheet', () {
    testWidgets('signed in: three pages, a rule, then the account itself', (
      tester,
    ) async {
      await pump(tester, user: _Account());
      await openSheet(tester);
      expect(sheetLabels(tester), [
        'Support',
        'Privacy',
        'Terms',
        'Sign out',
        'Delete account',
        if (kDebugTools) 'Debug',
        'Cancel',
      ]);
      // One rule, between the pages and the account actions.
      final rule = find.descendant(
        of: find.ancestor(
          of: find.text('Support'),
          matching: find.byType(Material),
        ).last,
        matching: find.byType(ColoredBox),
      );
      expect(rule, findsOneWidget);
      expect(
        tester.getRect(rule).top,
        greaterThan(tester.getRect(find.text('Terms')).bottom),
      );
      expect(
        tester.getRect(rule).bottom,
        lessThan(tester.getRect(find.text('Sign out')).top),
      );
    });

    testWidgets('a guest is offered the pages and nothing else', (
      tester,
    ) async {
      await pump(tester);
      await openSheet(tester);
      expect(sheetLabels(tester), [
        'Support',
        'Privacy',
        'Terms',
        if (kDebugTools) 'Debug',
        'Cancel',
      ]);
      expect(find.text('Delete account'), findsNothing);
      expect(find.text('Sign out'), findsNothing);
      // No rule either: there is nothing to part.
      expect(
        find.descendant(
          of: find.ancestor(
            of: find.text('Support'),
            matching: find.byType(Material),
          ).last,
          matching: find.byType(ColoredBox),
        ),
        findsNothing,
      );
    });

    testWidgets('the tones: pages white, account actions grey, both bold', (
      tester,
    ) async {
      await pump(tester, user: _Account());
      await openSheet(tester);
      final tokens = GreyscaleTokens.of(
        tester.element(find.byType(AccountBody)),
      );
      for (final page in ['Support', 'Privacy', 'Terms']) {
        final text = tester.widget<Text>(find.text(page));
        expect(text.style!.color, tokens.textPrimary, reason: page);
        expect(text.style!.fontWeight, FontWeight.w700, reason: page);
      }
      for (final action in ['Sign out', 'Delete account']) {
        final text = tester.widget<Text>(find.text(action));
        expect(text.style!.color, tokens.textSecondary, reason: action);
        expect(text.style!.fontWeight, FontWeight.w700, reason: action);
      }
      // Cancel is the exit: the same grey, regular weight.
      final cancel = tester.widget<Text>(find.text('Cancel'));
      expect(cancel.style!.color, tokens.textSecondary);
      expect(cancel.style!.fontWeight, FontWeight.w400);
      expect(tokens.textPrimary, const Color(0xFFFAFAFA));
      expect(tokens.textSecondary, const Color(0xFFB0B0B0));
    });

    testWidgets('mid-screen, never under the word that opened it', (
      tester,
    ) async {
      await pump(tester, user: _Account());
      final word = tester.getRect(find.text('More'));
      await openSheet(tester);
      final support = tester.getRect(find.text('Support'));
      final cancel = tester.getRect(find.text('Cancel'));
      expect(support.center.dy, lessThan(kRefHeight / 2));
      expect(cancel.center.dy, greaterThan(kRefHeight / 2));
      for (final label in ['Support', 'Sign out', 'Delete account', 'Cancel']) {
        expect(
          word.contains(tester.getRect(find.text(label)).center),
          isFalse,
          reason: '$label sits under More',
        );
      }
    });

    testWidgets('each page opens its own URL in the in-app browser', (
      tester,
    ) async {
      for (final (label, url) in [
        ('Support', 'https://s-ndr.com/support'),
        ('Privacy', 'https://s-ndr.com/privacy'),
        ('Terms', 'https://s-ndr.com/terms'),
      ]) {
        await pump(tester, user: _Account());
        await openSheet(tester);
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(pages.opened.last, url, reason: label);
      }
      expect(pages.opened.length, 3);
    });

    testWidgets('Cancel does nothing at all', (tester) async {
      await pump(tester, user: _Account());
      await openSheet(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(pages.opened, isEmpty);
      expect(find.text('Support'), findsNothing);
      expect(find.text('More'), findsOneWidget);
    });

    test('what each choice is offered to', () {
      expect(moreChoicesFor(signedIn: true), [
        MoreChoice.support,
        MoreChoice.privacy,
        MoreChoice.terms,
        MoreChoice.signOut,
        MoreChoice.deleteAccount,
        if (kDebugTools) MoreChoice.debug,
      ]);
      expect(moreChoicesFor(signedIn: false), [
        MoreChoice.support,
        MoreChoice.privacy,
        MoreChoice.terms,
        if (kDebugTools) MoreChoice.debug,
      ]);
      // A guest is never offered the deletion, whatever the build.
      expect(
        moreChoicesFor(signedIn: false),
        isNot(contains(MoreChoice.deleteAccount)),
      );
    });

    testWidgets('Debug is there only in a DEBUG_TOOLS build', (tester) async {
      await pump(tester, user: _Account());
      await openSheet(tester);
      expect(
        find.text('Debug'),
        kDebugTools ? findsOneWidget : findsNothing,
      );
      if (!kDebugTools) {
        expect(find.byType(DebugPanel), findsNothing);
      }
    });

    test('the words themselves', () {
      // Pinned because they are what the App Store review notes point at.
      expect(kDeleteAccountTitle, 'Delete your account?');
      expect(
        kDeleteAccountBody,
        'This permanently deletes your account, tracked time, photos, posts, '
        "comments and friends. It can't be undone.",
      );
      expect(kDeleteAccountConfirm, 'Delete account');
      expect(kPasswordPrompt, 'Enter your password to confirm');
      expect(kDeleteAccountFailed, "Couldn't delete your account. Try again.");
      expect(kAccountDeleted, 'Your account has been deleted.');
    });
  });
}

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/auth/account_cascade.dart';
import 'package:sondr/features/auth/auth_repository.dart';
import 'package:sondr/features/auth/delete_account.dart';
import 'package:sondr/features/timer/home_notice.dart';
import 'package:sondr/features/timer/live_activity.dart';
import 'package:sondr/features/timer/session_clock.dart';
import 'package:sondr/features/timer/session_store.dart';

import 'support/app_viewport.dart';

/// Deleting an account: the order, and what each refusal leaves behind.
///
/// The order IS the design. Nothing is deleted until the person has said
/// yes AND proved who they are, the Auth user goes last so a failure
/// anywhere above it leaves an account to retry as, and a fresh guest takes
/// its place so the app always has a uid.

/// Everything the flow did, in the order it did it.
class _Steps {
  final List<String> order = [];
}

class _Auth implements AuthRepository {
  _Auth(this.steps, {required this.providers, this.reauthThrows = false});

  final _Steps steps;
  final Set<String> providers;
  final bool reauthThrows;
  final List<String> passwords = [];

  @override
  Set<String> get providerIds => providers;

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    passwords.add(password);
    steps.order.add('reauth:password');
    if (reauthThrows) {
      throw FirebaseAuthException(code: 'wrong-password');
    }
  }

  @override
  Future<void> reauthenticateWithApple() async {
    steps.order.add('reauth:apple');
    if (reauthThrows) {
      throw FirebaseAuthException(code: 'cancelled');
    }
  }

  @override
  Future<void> deleteCurrentUser() async => steps.order.add('deleteUser');

  @override
  Future<void> signInAnonymously() async => steps.order.add('anonymous');

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _Erasure implements AccountErasure {
  _Erasure(this.steps, {this.throws = false});

  final _Steps steps;
  final bool throws;
  int runs = 0;

  @override
  Future<Set<String>> run() async {
    runs++;
    steps.order.add('cascade');
    if (throws) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return {'https://example.invalid/a.jpg'};
  }
}

class _Caches implements LocalCaches {
  _Caches(this.steps);

  final _Steps steps;
  Set<String>? evicted;

  @override
  Future<void> clear(Set<String> photoUrls) async {
    steps.order.add('caches');
    evicted = photoUrls;
  }
}

class _Card implements LiveActivity {
  _Card(this.steps);

  final _Steps steps;

  @override
  Future<void> clear() async => steps.order.add('card');

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

/// Nothing on the other end of the platform channel, and nothing needed:
/// the flow discards whatever is there.
class _NoStore implements SessionStore {
  @override
  Future<SessionClock?> read() async => null;

  @override
  Future<void> write(SessionClock clock) async {}

  @override
  Future<void> clear() async {}
}

void main() {
  late _Steps steps;
  late _Auth auth;
  late _Erasure erasure;
  late _Caches caches;
  late ProviderContainer container;

  /// Set when the flow returns, which is after the interaction — so it is
  /// read at the END of a test, never from pump's return value.
  DeleteAccountOutcome? outcome;

  Future<void> pump(
    WidgetTester tester, {
    Set<String> providers = const {'password'},
    bool reauthThrows = false,
    bool cascadeThrows = false,
  }) async {
    steps = _Steps();
    auth = _Auth(steps, providers: providers, reauthThrows: reauthThrows);
    erasure = _Erasure(steps, throws: cascadeThrows);
    caches = _Caches(steps);
    outcome = null;

    useReferenceViewport(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          accountCascadeProvider.overrideWithValue(erasure),
          localCachesProvider.overrideWithValue(caches),
          liveActivityProvider.overrideWithValue(_Card(steps)),
          sessionStoreProvider.overrideWithValue(_NoStore()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Consumer(
            builder: (context, ref, _) {
              container = ProviderScope.containerOf(context);
              return Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async =>
                        outcome = await deleteAccount(context, ref),
                    child: const Text('go'),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  /// The confirm, then the password prompt, then the deletion.
  Future<void> throughIt(WidgetTester tester, {String password = 'pw'}) async {
    await tester.tap(find.text(kDeleteAccountConfirm));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), password);
    await tester.pumpAndSettle();
    await tester.tap(find.text(kDeleteAccountConfirm));
    await tester.pumpAndSettle();
  }

  group('the question', () {
    testWidgets('names everything that goes, and that it cannot be undone', (
      tester,
    ) async {
      await pump(tester);
      expect(find.text(kDeleteAccountTitle), findsOneWidget);
      expect(find.text(kDeleteAccountBody), findsOneWidget);
      expect(find.text(kDeleteAccountConfirm), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('Cancel deletes nothing, and asks for no password', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(steps.order, isEmpty);
      expect(find.byType(TextField), findsNothing);
    });
  });

  group('proving who is asking', () {
    testWidgets('an email account is asked for its password', (tester) async {
      await pump(tester);
      await tester.tap(find.text(kDeleteAccountConfirm));
      await tester.pumpAndSettle();
      expect(find.text(kPasswordPrompt), findsOneWidget);
      // Obscured, uncapitalised, uncorrected: it is a password.
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
      expect(field.autocorrect, isFalse);
      expect(field.textCapitalization, TextCapitalization.none);
    });

    testWidgets('cancelling the password deletes NOTHING', (tester) async {
      await pump(tester);
      await tester.tap(find.text(kDeleteAccountConfirm));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(steps.order, isEmpty, reason: 'it got past the password');
      expect(erasure.runs, 0);
      expect(outcome, DeleteAccountOutcome.cancelled);
    });

    testWidgets('a wrong password deletes nothing and says so', (tester) async {
      await pump(tester, reauthThrows: true);
      await throughIt(tester, password: 'wrong');

      expect(auth.passwords, ['wrong']);
      expect(steps.order, ['reauth:password']);
      expect(erasure.runs, 0, reason: 'it deleted data on a failed re-auth');
    });

    testWidgets('an Apple account goes through Apple, with no password', (
      tester,
    ) async {
      await pump(tester, providers: {'apple.com'});
      await tester.tap(find.text(kDeleteAccountConfirm));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(steps.order.first, 'reauth:apple');
    });

    testWidgets('a dismissed Apple sheet deletes nothing', (tester) async {
      await pump(tester, providers: {'apple.com'}, reauthThrows: true);
      await tester.tap(find.text(kDeleteAccountConfirm));
      await tester.pumpAndSettle();
      expect(steps.order, ['reauth:apple']);
      expect(erasure.runs, 0);
    });

    testWidgets('an account with neither provider is not deleted', (
      tester,
    ) async {
      await pump(tester, providers: const {});
      await tester.tap(find.text(kDeleteAccountConfirm));
      await tester.pumpAndSettle();
      expect(steps.order, isEmpty);
      expect(outcome, DeleteAccountOutcome.failed);
    });
  });

  group('the order it happens in', () {
    testWidgets('card, session, cascade, user, guest, caches', (tester) async {
      await pump(tester);
      await throughIt(tester);

      // The card is cleared by the flow and again by discard(), which
      // takes its own card down — so it is counted once here and placed
      // by where it falls.
      expect(steps.order.contains('card'), isTrue);
      expect(
        steps.order.indexOf('card'),
        lessThan(steps.order.indexOf('cascade')),
        reason: 'the Lock Screen card outlived the account',
      );
      expect([for (final step in steps.order) if (step != 'card') step], [
        'reauth:password',
        'cascade',
        // LAST, so everything above it had an account to run as.
        'deleteUser',
        'anonymous',
        'caches',
      ]);
      expect(outcome, DeleteAccountOutcome.deleted);
    });

    testWidgets('the photo URLs the cascade found are evicted', (
      tester,
    ) async {
      await pump(tester);
      await throughIt(tester);
      expect(caches.evicted, {'https://example.invalid/a.jpg'});
    });

    testWidgets('Home is left with the one line that explains it', (
      tester,
    ) async {
      await pump(tester);
      await throughIt(tester);
      expect(container.read(homeNoticeProvider), kAccountDeleted);
    });

    testWidgets('a cascade that fails keeps the account', (tester) async {
      await pump(tester, cascadeThrows: true);
      await throughIt(tester);

      expect([for (final step in steps.order) if (step != 'card') step], [
        'reauth:password',
        'cascade',
      ]);
      expect(
        steps.order,
        isNot(contains('deleteUser')),
        reason: 'the account was deleted after a failed cascade',
      );
      expect(outcome, DeleteAccountOutcome.failed);
      expect(container.read(homeNoticeProvider), isNull);
    });
  });

  group('the Apple side of it', () {
    /// Apple requires the token to be revoked when an account is deleted,
    /// and revocation takes the authorization code from THIS trip through
    /// the sheet — the code is one-shot, so the one kept from the original
    /// sign-in is long spent.
    test('a fresh trip, re-authenticated then revoked, in that order', () async {
      final apple = _FakeApple();
      final user = _FakeUser();
      final firebase = _FakeFirebaseAuth(user);
      final repo = AuthRepository(firebase, authorize: apple.authorize);

      await repo.reauthenticateWithApple();

      expect(apple.calls, 1, reason: 'Apple was not asked again');
      expect(user.reauthenticatedWith.length, 1);
      // The code from this trip, not a remembered one.
      expect(firebase.revoked, ['code-1']);
      expect(user.order, ['reauth']);
      expect(firebase.order, ['revoke']);

      // A second deletion attempt mints a new nonce and a new code.
      await repo.reauthenticateWithApple();
      expect(apple.noncesSeen.toSet().length, 2, reason: 'the nonce repeated');
      expect(firebase.revoked, ['code-1', 'code-2']);
    });

    test('a token with no code is not revoked, and does not throw', () async {
      final apple = _FakeApple(code: null);
      final user = _FakeUser();
      final firebase = _FakeFirebaseAuth(user);
      final repo = AuthRepository(firebase, authorize: apple.authorize);

      await repo.reauthenticateWithApple();
      expect(user.reauthenticatedWith.length, 1);
      expect(firebase.revoked, isEmpty);
    });
  });
}

/// Hands back a distinct token and code per trip, and records the nonces.
class _FakeApple {
  _FakeApple({this.code = 'code'});

  final String? code;
  int calls = 0;
  final List<String> noncesSeen = [];

  Future<AuthorizationCredentialAppleID> authorize(String nonce) async {
    calls++;
    noncesSeen.add(nonce);
    return AuthorizationCredentialAppleID(
      userIdentifier: 'apple-user',
      givenName: 'A',
      familyName: 'B',
      authorizationCode: code == null ? '' : '$code-$calls',
      email: null,
      identityToken: 'token-$calls',
      state: null,
    );
  }
}

class _FakeUser implements User {
  final List<AuthCredential> reauthenticatedWith = [];
  final List<String> order = [];

  @override
  bool get isAnonymous => false;

  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    reauthenticatedWith.add(credential);
    order.add('reauth');
    return _FakeUserCredential();
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeFirebaseAuth implements FirebaseAuth {
  _FakeFirebaseAuth(this._user);

  final _FakeUser _user;
  final List<String> revoked = [];
  final List<String> order = [];

  @override
  User? get currentUser => _user;

  @override
  Future<void> revokeTokenWithAuthorizationCode(String code) async {
    revoked.add(code);
    order.add('revoke');
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

class _FakeUserCredential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

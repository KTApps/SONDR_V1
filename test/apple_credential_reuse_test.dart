import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:sondr/features/auth/auth_repository.dart';

/// A nonce is ONE SHOT.
///
/// When the Apple identity already belongs to another account, the link fails
/// with `credential-already-in-use` or `email-already-in-use` and the flow
/// signs into that account instead. It used to present the SAME credential to
/// do it — the one whose nonce Firebase had just consumed verifying the link —
/// which comes back as `missing-or-invalid-nonce`: an error about the nonce,
/// raised on a flow whose nonce was never wrong, which is exactly how long
/// this took to find.
void main() {
  late _FakeApple apple;

  setUp(() => apple = _FakeApple());

  /// The credential a given `link` failure hands back, if any.
  Future<_Harness> run({
    required String linkFailureCode,
    AuthCredential? carried,
  }) async {
    final user = _FakeUser(
      onLink: (_) => throw FirebaseAuthException(
        code: linkFailureCode,
        credential: carried,
      ),
    );
    final auth = _FakeFirebaseAuth(user);
    final repo = AuthRepository(auth, authorize: apple.authorize);
    await repo.signInWithApple(confirmReplaceGuest: () async => true);
    return _Harness(auth: auth, user: user, apple: apple);
  }

  for (final code in ['credential-already-in-use', 'email-already-in-use']) {
    testWidgets('$code signs in with the credential the EXCEPTION carried', (
      tester,
    ) async {
      final carried = OAuthProvider('apple.com').credential(
        idToken: 'carried-token',
        rawNonce: 'carried-nonce',
      );
      final h = await run(linkFailureCode: code, carried: carried);

      // It signed in exactly once, with the exception's credential.
      expect(h.auth.signedInWith, hasLength(1));
      expect(h.auth.signedInWith.single, same(carried));
      // And NOT with the one the link already spent.
      expect(h.user.linkedWith, hasLength(1));
      expect(
        h.auth.signedInWith.single,
        isNot(same(h.user.linkedWith.single)),
        reason: 'the used credential was presented a second time',
      );
      // No second trip through Apple was needed.
      expect(h.apple.calls, 1);
    });
  }

  testWidgets('with nothing carried, Apple is asked again for a FRESH nonce', (
    tester,
  ) async {
    final h = await run(linkFailureCode: 'credential-already-in-use');

    expect(h.apple.calls, 2, reason: 'a fresh authorization was not taken');
    // Each trip minted its own nonce.
    expect(h.apple.noncesSeen.toSet(), hasLength(2));
    expect(h.auth.signedInWith, hasLength(1));
    // The second credential, never the first.
    expect(
      h.auth.signedInWith.single,
      isNot(same(h.user.linkedWith.single)),
      reason: 'the used credential was presented a second time',
    );
    final signedIn = h.auth.signedInWith.single as OAuthCredential;
    expect(signedIn.idToken, 'token-2');
  });

  testWidgets('a link failure that is neither is tagged as the LINK step', (
    tester,
  ) async {
    final user = _FakeUser(
      onLink: (_) =>
          throw FirebaseAuthException(code: 'missing-or-invalid-nonce'),
    );
    final auth = _FakeFirebaseAuth(user);
    await expectLater(
      AuthRepository(auth, authorize: apple.authorize).signInWithApple(),
      throwsA(
        isA<AppleStepException>()
            .having((e) => e.step, 'step', AppleStep.link)
            .having((e) => e.code, 'code', 'missing-or-invalid-nonce')
            .having((e) => e.stepName, 'stepName', 'link'),
      ),
    );
    expect(auth.signedInWith, isEmpty);
  });

  testWidgets('a signed-in (non-guest) user is tagged as the SIGN-IN step', (
    tester,
  ) async {
    final auth = _FakeFirebaseAuth(
      _FakeUser(onLink: (_) => throw UnimplementedError(), anonymous: false),
      onSignIn: (_) => throw FirebaseAuthException(code: 'invalid-credential'),
    );
    await expectLater(
      AuthRepository(auth, authorize: apple.authorize).signInWithApple(),
      throwsA(
        isA<AppleStepException>()
            .having((e) => e.step, 'step', AppleStep.signIn)
            .having((e) => e.code, 'code', 'invalid-credential'),
      ),
    );
  });

  testWidgets('declining to replace the guest changes nothing', (tester) async {
    final user = _FakeUser(
      onLink: (_) =>
          throw FirebaseAuthException(code: 'credential-already-in-use'),
    );
    final auth = _FakeFirebaseAuth(user);
    final result = await AuthRepository(
      auth,
      authorize: apple.authorize,
    ).signInWithApple(confirmReplaceGuest: () async => false);
    expect(result.cancelled, isTrue);
    expect(auth.signedInWith, isEmpty);
    // And Apple was not asked a second time for a sign-in that is not happening.
    expect(apple.calls, 1);
  });
}

class _Harness {
  _Harness({required this.auth, required this.user, required this.apple});
  final _FakeFirebaseAuth auth;
  final _FakeUser user;
  final _FakeApple apple;
}

/// Hands back a distinct identity token per trip, and records the nonces.
class _FakeApple {
  int calls = 0;
  final List<String> noncesSeen = [];

  Future<AuthorizationCredentialAppleID> authorize(String nonce) async {
    calls++;
    noncesSeen.add(nonce);
    return AuthorizationCredentialAppleID(
      userIdentifier: 'apple-user',
      givenName: 'A',
      familyName: 'B',
      authorizationCode: 'code-$calls',
      email: null,
      identityToken: 'token-$calls',
      state: null,
    );
  }
}

class _FakeFirebaseAuth implements FirebaseAuth {
  _FakeFirebaseAuth(this._user, {this.onSignIn});

  final _FakeUser _user;
  final Future<UserCredential> Function(AuthCredential)? onSignIn;
  final List<AuthCredential> signedInWith = [];

  @override
  User? get currentUser => _user;

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) {
    signedInWith.add(credential);
    if (onSignIn != null) return onSignIn!(credential);
    return Future.value(_FakeUserCredential());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeUser implements User {
  _FakeUser({required this.onLink, this.anonymous = true});

  final Future<UserCredential> Function(AuthCredential) onLink;
  final bool anonymous;
  final List<AuthCredential> linkedWith = [];

  @override
  bool get isAnonymous => anonymous;

  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) {
    linkedWith.add(credential);
    return onLink(credential);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeUserCredential implements UserCredential {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

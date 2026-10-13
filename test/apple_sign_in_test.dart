import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:sondr/core/backend.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/features/auth/apple_sign_in_button.dart';
import 'package:sondr/features/auth/auth_repository.dart';
import 'package:sondr/features/auth/models/profile.dart';
import 'package:sondr/features/auth/profile_repository.dart';

/// What the Apple button says when things go wrong.
///
/// The first real-device attempt failed with "Could not sign in with Apple",
/// and the diagnosis cost a round of checking entitlements, the bundle id and
/// the Firebase provider — all of which were correct — because that one
/// sentence covered the whole flow, including the Firestore read AFTER a
/// successful sign-in, and nothing logged a code.
void main() {
  Future<void> pumpButton(
    WidgetTester tester, {
    required AuthRepository auth,
    ProfileRepository? profiles,
    String? uid = 'me',
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          profileRepositoryProvider.overrideWithValue(profiles),
          currentUidProvider.overrideWithValue(uid),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: Center(child: AppleSignInButton()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapIt(WidgetTester tester) async {
    await tester.tap(find.text('Sign in with Apple'));
    await tester.pumpAndSettle();
  }

  group('a failure to authenticate', () {
    testWidgets('names Apple, and nothing else', (tester) async {
      await pumpButton(
        tester,
        auth: _FakeAuth(
          () => throw const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.failed,
            message: 'nope',
          ),
        ),
      );
      await tapIt(tester);
      expect(find.text(kAppleSignInFailed), findsOneWidget);
      expect(find.text(kAppleProfileFailed), findsNothing);
    });

    testWidgets('is SILENT when the user backs out of the sheet', (
      tester,
    ) async {
      await pumpButton(
        tester,
        auth: _FakeAuth(
          () => throw const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.canceled,
            message: 'cancelled',
          ),
        ),
      );
      await tapIt(tester);
      expect(find.textContaining('Could not sign in'), findsNothing);
      expect(find.textContaining('Signed in, but'), findsNothing);
      // And the button is usable again.
      expect(find.text('Sign in with Apple'), findsOneWidget);
    });

    testWidgets('names Apple for a Firebase failure too', (tester) async {
      await pumpButton(
        tester,
        auth: _FakeAuth(
          () => throw FirebaseAuthException(code: 'invalid-credential'),
        ),
      );
      await tapIt(tester);
      expect(find.text(kAppleSignInFailed), findsOneWidget);
    });
  });

  group('a failure AFTER authenticating', () {
    testWidgets('says so, instead of blaming Apple', (tester) async {
      await pumpButton(
        tester,
        auth: _FakeAuth(() async => const AppleSignInResult()),
        profiles: _ThrowingProfiles(),
      );
      await tapIt(tester);
      // The distinction this file exists for.
      expect(find.text(kAppleProfileFailed), findsOneWidget);
      expect(find.text(kAppleSignInFailed), findsNothing);
    });
  });

  group('the code suffix', () {
    // kDebugTools is const-false in a test run, so the switch is exercised
    // through the function rather than through a build.
    test('is appended only for DEBUG_TOOLS builds', () {
      expect(
        appleErrorText(kAppleSignInFailed, 'invalid-credential',
            withCode: true),
        '$kAppleSignInFailed (invalid-credential)',
      );
      expect(
        appleErrorText(kAppleSignInFailed, 'invalid-credential',
            withCode: false),
        kAppleSignInFailed,
      );
      // Nothing to append is nothing to append, either way.
      expect(appleErrorText(kAppleSignInFailed, null, withCode: true),
          kAppleSignInFailed);
      expect(appleErrorText(kAppleSignInFailed, '', withCode: true),
          kAppleSignInFailed);
    });

    test('release copy is unchanged', () {
      expect(kAppleSignInFailed, 'Could not sign in with Apple. Please try again.');
      expect(kAppleProfileFailed,
          'Signed in, but couldn’t load your profile. Please try again.');
    });
  });
}

class _FakeAuth implements AuthRepository {
  _FakeAuth(this.onApple);

  final Future<AppleSignInResult> Function() onApple;

  @override
  Future<AppleSignInResult> signInWithApple({
    Future<bool> Function()? confirmReplaceGuest,
  }) => onApple();

  @override
  User? get currentUser => null;
  @override
  bool get isAnonymous => true;
  @override
  Future<void> signUpWithEmail(String email, String password) async =>
      throw UnimplementedError();
  @override
  Future<void> signInWithEmail(String email, String password) async =>
      throw UnimplementedError();
  @override
  Future<void> signOut() async => throw UnimplementedError();
}

class _ThrowingProfiles implements ProfileRepository {
  @override
  Future<Profile?> fetch(String uid) async =>
      throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

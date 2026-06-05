import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// The display name Apple hands back on the very first sign-in only (it returns
/// the name exactly once). Carried out of [AuthRepository.signInWithApple] so
/// the caller can seed the profile before the chance is gone.
class AppleSignInResult {
  const AppleSignInResult({this.displayName});

  /// `null` on every subsequent sign-in, and whenever the user hides their name.
  final String? displayName;
}

/// Wraps FirebaseAuth so the rest of the app never talks to it directly. Two
/// sign-in paths share the same link-or-create logic: email/password and
/// Sign in with Apple. Both **link** onto a guest (anonymous) account when one
/// exists, so the uid — and all of its tasks/habits — carries over.
class AuthRepository {
  AuthRepository(this._auth);

  final FirebaseAuth _auth;

  User? get currentUser => _auth.currentUser;
  bool get isAnonymous => _auth.currentUser?.isAnonymous ?? true;

  /// Create a permanent email/password account. If the user is currently a
  /// guest (anonymous), **link** the credential so the uid — and all of its
  /// tasks/habits — is preserved. Otherwise create a fresh account.
  Future<void> signUpWithEmail(String email, String password) async {
    final credential = EmailAuthProvider.credential(
      email: email.trim(),
      password: password,
    );
    final user = _auth.currentUser;
    if (user != null && user.isAnonymous) {
      await user.linkWithCredential(credential);
    } else {
      await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    }
  }

  /// Sign in to an existing email account (returning user).
  Future<void> signInWithEmail(String email, String password) async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Sign in (or sign up) with Apple. One button covers both cases: if this is
  /// a new Apple identity it becomes a permanent account; if it already maps to
  /// a Firebase user we sign into that one.
  ///
  /// Mirrors [signUpWithEmail]: a guest (anonymous) account is **linked** in
  /// place so its uid and data survive. If the Apple identity is already bound
  /// to a different Firebase user (`credential-already-in-use`), we fall back to
  /// signing into that account — the guest session is discarded.
  ///
  /// The nonce defeats replay attacks: Apple signs the SHA-256 of it into the
  /// id-token, and Firebase checks the raw value against that hash.
  Future<AppleSignInResult> signInWithApple() async {
    final rawNonce = _generateNonce();
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: _sha256(rawNonce),
    );

    // Firebase needs BOTH the identity token (with the raw nonce to verify the
    // hash Apple signed in) AND Apple's authorization code as the accessToken.
    // Omitting the authorizationCode yields a misleading
    // `invalid-credential: Invalid OAuth response from apple.com`.
    final oauth = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
      accessToken: appleCredential.authorizationCode,
    );

    // Apple returns the name only on first authorization — capture it now.
    final displayName = _composeName(
      appleCredential.givenName,
      appleCredential.familyName,
    );

    final user = _auth.currentUser;
    if (user != null && user.isAnonymous) {
      try {
        await user.linkWithCredential(oauth);
      } on FirebaseAuthException catch (e) {
        // Apple ID already belongs to another account → sign into that one.
        if (e.code == 'credential-already-in-use' ||
            e.code == 'email-already-in-use') {
          await _auth.signInWithCredential(oauth);
        } else {
          rethrow;
        }
      }
    } else {
      await _auth.signInWithCredential(oauth);
    }

    return AppleSignInResult(displayName: displayName);
  }

  /// A cryptographically secure random nonce (Apple requires hashing this).
  String _generateNonce([int length = 32]) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  String _sha256(String input) =>
      sha256.convert(utf8.encode(input)).toString();

  String? _composeName(String? given, String? family) {
    final parts = [given, family]
        .where((p) => p != null && p.trim().isNotEmpty)
        .map((p) => p!.trim());
    final name = parts.join(' ');
    return name.isEmpty ? null : name;
  }

  /// Sign out, then immediately start a fresh guest session so the app always
  /// has a uid and stays on the Firestore backend.
  Future<void> signOut() async {
    await _auth.signOut();
    await _auth.signInAnonymously();
  }
}

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository(FirebaseAuth.instance));

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
  const AppleSignInResult({this.displayName, this.cancelled = false});

  /// `null` on every subsequent sign-in, and whenever the user hides their name.
  final String? displayName;

  /// True when the user declined to replace their guest data with the existing
  /// account the Apple ID belongs to — nothing changed.
  final bool cancelled;
}

/// Which step of the Apple flow failed.
///
/// The steps can fail for entirely different reasons and the codes overlap, so
/// a device report that says only `missing-or-invalid-nonce` does not say
/// whether the nonce was rejected on the way in or on a second use of a
/// credential that had already spent it. This names the step.
/// Apple's own step is absent on purpose: its failures arrive already typed,
/// as [SignInWithAppleAuthorizationException], and wrapping them would hide
/// the cancellation the button has to stay silent about.
enum AppleStep {
  /// Linking the Apple identity onto the signed-in guest.
  link,

  /// Signing into the account the Apple identity already belongs to.
  signIn,
}

/// An error from one named step of the Apple flow, with the original intact.
class AppleStepException implements Exception {
  const AppleStepException(this.step, this.cause);

  final AppleStep step;
  final Object cause;

  /// `link` / `signIn` / `apple`, as it appears in a DEBUG_TOOLS message.
  String get stepName => step.name;

  /// The provider's own code, where the cause carries one.
  String? get code {
    final error = cause;
    if (error is FirebaseAuthException) return error.code;
    if (error is FirebaseException) return error.code;
    return null;
  }

  @override
  String toString() => 'AppleStepException(${step.name}: ${code ?? cause})';
}

/// One authorization from Apple, and the name it carried.
class _AppleAuthorization {
  const _AppleAuthorization({required this.credential, this.displayName});

  final AuthCredential credential;
  final String? displayName;
}

/// Wraps FirebaseAuth so the rest of the app never talks to it directly. Two
/// sign-in paths share the same link-or-create logic: email/password and
/// Sign in with Apple. Both **link** onto a guest (anonymous) account when one
/// exists, so the uid — and all of its tasks/habits — carries over.
/// The one platform call in the Apple flow, as a seam.
///
/// Takes the nonce to embed in the identity token and returns what Apple
/// handed back. Injected only by tests: the flow's correctness is entirely
/// about how many times this is called and with which nonce, and neither is
/// observable through the static plugin entry point.
typedef AppleAuthorize =
    Future<AuthorizationCredentialAppleID> Function(String nonce);

class AuthRepository {
  AuthRepository(this._auth, {AppleAuthorize? authorize})
    : _authorize = authorize ?? _appleAuthorize;

  final FirebaseAuth _auth;
  final AppleAuthorize _authorize;

  static Future<AuthorizationCredentialAppleID> _appleAuthorize(
    String nonce,
  ) => SignInWithApple.getAppleIDCredential(
    scopes: [
      AppleIDAuthorizationScopes.email,
      AppleIDAuthorizationScopes.fullName,
    ],
    nonce: nonce,
  );

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
  /// signing into that account — the guest session is discarded, so
  /// [confirmReplaceGuest] is asked first; returning false cancels.
  ///
  /// The nonce defeats replay attacks: Apple signs the SHA-256 of it into the
  /// id-token, and Firebase checks the raw value against that hash.
  Future<AppleSignInResult> signInWithApple({
    Future<bool> Function()? confirmReplaceGuest,
  }) async {
    final first = await _authorizeWithApple();

    final user = _auth.currentUser;
    if (user != null && user.isAnonymous) {
      try {
        await user.linkWithCredential(first.credential);
      } on FirebaseAuthException catch (e) {
        // Apple ID already belongs to another account → sign into that one.
        if (e.code == 'credential-already-in-use' ||
            e.code == 'email-already-in-use') {
          if (confirmReplaceGuest != null && !await confirmReplaceGuest()) {
            return const AppleSignInResult(cancelled: true);
          }
          // NEVER the credential the link just used. A nonce is ONE SHOT:
          // Firebase consumed it verifying the link, and presenting it again
          // comes back as `missing-or-invalid-nonce` — an error about the
          // nonce, on a flow whose nonce was never wrong, which is how this
          // cost a round of looking at the hashing.
          //
          // The exception carries a usable credential for exactly this
          // case. When it does not, Apple is asked again, which mints a
          // fresh nonce with it.
          final AuthCredential replacement =
              e.credential ?? (await _authorizeWithApple()).credential;
          try {
            await _auth.signInWithCredential(replacement);
          } catch (signInError) {
            throw AppleStepException(AppleStep.signIn, signInError);
          }
        } else {
          throw AppleStepException(AppleStep.link, e);
        }
      } catch (e) {
        throw AppleStepException(AppleStep.link, e);
      }
    } else {
      try {
        await _auth.signInWithCredential(first.credential);
      } catch (e) {
        throw AppleStepException(AppleStep.signIn, e);
      }
    }

    return AppleSignInResult(displayName: first.displayName);
  }

  /// One trip through Apple's sheet: a FRESH nonce, and the credential it
  /// produced.
  ///
  /// The nonce defeats replay attacks. Apple embeds whatever string it is
  /// given into the identity token verbatim — the plugin does no hashing — so
  /// it is given the SHA-256 of the raw value and Firebase is given the raw
  /// value to hash and compare. One nonce, one credential, one use.
  Future<_AppleAuthorization> _authorizeWithApple() async {
    final rawNonce = _generateNonce();
    final appleCredential = await _authorize(_sha256(rawNonce));

    // Firebase needs BOTH the identity token (with the raw nonce to verify the
    // hash Apple signed in) AND Apple's authorization code as the accessToken.
    // Omitting the authorizationCode yields a misleading
    // `invalid-credential: Invalid OAuth response from apple.com`.
    final oauth = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
      accessToken: appleCredential.authorizationCode,
    );

    return _AppleAuthorization(
      credential: oauth,
      // Apple returns the name only on first authorization — capture it now.
      displayName: _composeName(
        appleCredential.givenName,
        appleCredential.familyName,
      ),
    );
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

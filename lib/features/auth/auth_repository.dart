import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wraps FirebaseAuth so the rest of the app never talks to it directly. The
/// email/password path is complete; **Sign in with Apple slots in here later**
/// as another method (e.g. `signInWithApple()` building an `OAuthProvider`
/// credential and reusing the same link/sign-in logic).
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

  /// Sign out, then immediately start a fresh guest session so the app always
  /// has a uid and stays on the Firestore backend.
  Future<void> signOut() async {
    await _auth.signOut();
    await _auth.signInAnonymously();
  }
}

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository(FirebaseAuth.instance));

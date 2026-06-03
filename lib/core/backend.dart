import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compile-time backend selector. Defaults to Firebase; force the local
/// in-memory backend with `flutter run --dart-define=USE_FIREBASE=false`.
const bool kUseFirebase =
    bool.fromEnvironment('USE_FIREBASE', defaultValue: true);

/// True once `Firebase.initializeApp` has succeeded. Overridden in `main()`;
/// defaults false so tests and the offline/init-failure fallback use the local
/// repositories.
final firebaseInitializedProvider = Provider<bool>((ref) => false);

/// The current Firebase user — anonymous (guest) or permanent — or null.
///
/// Uses `userChanges()` so it also emits on account **linking** (anonymous →
/// email), letting the UI and uid react when a guest upgrades in place. Returns
/// an inert stream when Firebase isn't initialised, so tests never touch
/// FirebaseAuth.
final authUserProvider = StreamProvider<User?>((ref) {
  if (!kUseFirebase || !ref.watch(firebaseInitializedProvider)) {
    return const Stream<User?>.empty();
  }
  return FirebaseAuth.instance.userChanges();
});

/// The uid that scopes all Firestore data. Falls back to the synchronously
/// available `currentUser` so there's no gap before the stream's first
/// emission. **Linking preserves the uid**, so existing data carries over
/// seamlessly when a guest becomes a permanent account.
final currentUidProvider = Provider<String?>((ref) {
  if (!kUseFirebase || !ref.watch(firebaseInitializedProvider)) return null;
  final streamed = ref.watch(authUserProvider).value;
  return streamed?.uid ?? FirebaseAuth.instance.currentUser?.uid;
});

/// True when the Firestore-backed repositories should be used.
final firebaseReadyProvider = Provider<bool>((ref) =>
    kUseFirebase &&
    ref.watch(firebaseInitializedProvider) &&
    ref.watch(currentUidProvider) != null);

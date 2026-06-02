import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compile-time backend selector. Defaults to Firebase; force the local
/// in-memory backend with `flutter run --dart-define=USE_FIREBASE=false`.
const bool kUseFirebase =
    bool.fromEnvironment('USE_FIREBASE', defaultValue: true);

/// True once Firebase has initialised and an (anonymous) user is signed in.
/// Overridden to true in `main()` on success; defaults false so that tests and
/// the offline/init-failure fallback transparently use the local repositories.
final firebaseReadyProvider = Provider<bool>((ref) => false);

/// The signed-in (anonymous) user id that scopes all Firestore data, or null
/// when Firebase isn't ready. Overridden in `main()`.
final currentUidProvider = Provider<String?>((ref) => null);

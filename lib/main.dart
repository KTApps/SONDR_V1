import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/backend.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Bring up Firebase and an anonymous session. On any failure (missing config,
  // offline first launch, init error) we fall through to the local in-memory
  // backend so the app always runs. ProviderScope overrides flip the repository
  // providers to Firestore only when this succeeds.
  String? uid;
  if (kUseFirebase) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final auth = FirebaseAuth.instance;
      final user =
          auth.currentUser ?? (await auth.signInAnonymously()).user;
      uid = user?.uid;
    } catch (e) {
      debugPrint('Firebase unavailable, using local backend: $e');
    }
  }

  final resolvedUid = uid;
  runApp(
    ProviderScope(
      overrides: resolvedUid == null
          ? const []
          : [
              firebaseReadyProvider.overrideWithValue(true),
              currentUidProvider.overrideWithValue(resolvedUid),
            ],
      child: const SondrApp(),
    ),
  );
}

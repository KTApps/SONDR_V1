import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/backend.dart';
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait-only — the layouts are designed for portrait (the iOS
  // UISupportedInterfaceOrientations enforces it at the OS level too).
  await SystemChrome.setPreferredOrientations(
    const [DeviceOrientation.portraitUp],
  );

  // Bring up Firebase and ensure there's always a user: a guest (anonymous)
  // session if no one is signed in, so data always has a home and can later be
  // upgraded in place to a permanent account. On any failure we fall through to
  // the local backend so the app still runs; tests never initialise Firebase.
  var initialized = false;
  if (kUseFirebase) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }
      initialized = true;
    } catch (e) {
      debugPrint('Firebase unavailable, using local backend: $e');
    }
  }

  runApp(
    ProviderScope(
      overrides: initialized
          ? [firebaseInitializedProvider.overrideWithValue(true)]
          : const [],
      child: const SondrApp(),
    ),
  );
}

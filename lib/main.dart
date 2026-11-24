import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/backend.dart';
import 'features/presence/presence_writer.dart';
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

  final container = ProviderContainer(
    overrides: initialized
        ? [firebaseInitializedProvider.overrideWithValue(true)]
        : const [],
  );
  // "In a session", for friends, kept in step for the app's whole life.
  // Held here rather than by a widget: a widget's providers pause while a
  // route covers it, and Stop deletes the record under the camera.
  container.listen(presenceWriterProvider, (_, _) {});
  runApp(
    UncontrolledProviderScope(container: container, child: const SondrApp()),
  );
}

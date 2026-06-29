import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/splash/boot_gate.dart';

/// Root widget. Wires both greyscale themes and lets the OS pick light/dark.
/// The home is the launch gate: a splash that holds until Home's data is
/// loaded, then cross-fades into the tab shell (Home · Feed · Profile).
class SondrApp extends StatelessWidget {
  const SondrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sondr',
      debugShowCheckedModeBanner: false,
      // Sondr is a dark greyscale app. Dark is the design; light exists only as
      // the inverted ladder for completeness, but the app runs dark.
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const BootGate(),
    );
  }
}

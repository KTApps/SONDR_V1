import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/showcase/ring_showcase_screen.dart';

/// Root widget. Wires both greyscale themes and lets the OS pick light/dark.
/// The home is currently the ring showcase (step 1); it will be replaced by the
/// timer screen in step 2.
class SondrApp extends StatelessWidget {
  const SondrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sondr',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const RingShowcaseScreen(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../feed/feed_screen.dart';
import '../focus/focus_providers.dart';
import '../profile/profile_screen.dart';
import '../timer/timer_screen.dart';

/// Root tab shell: Home · Feed · Profile. Introduced in step 2, it replaces the
/// phase-1 top-right buttons on the timer with a bottom [NavigationBar].
///
/// An [IndexedStack] keeps each tab alive so the running timer (and any scroll
/// position) survives tab switches. While Focus Mode is active the bar is hidden
/// and the shell is pinned to Home — the timer returns the quietened FocusView,
/// reinforcing the "locked into the effort" ethos.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  static const _tabs = [
    TimerScreen(),
    FeedScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final focused = ref.watch(focusModeProvider);

    return Scaffold(
      // Pin to Home while focused so the FocusView is what shows, never another
      // tab caught behind the hidden bar.
      body: IndexedStack(
        index: focused ? 0 : _index,
        children: _tabs,
      ),
      bottomNavigationBar: focused
          ? null
          : NavigationBarTheme(
              data: NavigationBarThemeData(
                backgroundColor: tokens.surface,
                indicatorColor: tokens.ringTrack,
                surfaceTintColor: Colors.transparent,
                iconTheme: WidgetStateProperty.resolveWith(
                  (states) => IconThemeData(
                    color: states.contains(WidgetState.selected)
                        ? tokens.textPrimary
                        : tokens.textTertiary,
                  ),
                ),
                labelTextStyle: WidgetStateProperty.resolveWith(
                  (states) => theme.textTheme.labelSmall?.copyWith(
                    color: states.contains(WidgetState.selected)
                        ? tokens.textPrimary
                        : tokens.textTertiary,
                  ),
                ),
              ),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.timer_outlined),
                    selectedIcon: Icon(Icons.timer),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.dynamic_feed_outlined),
                    selectedIcon: Icon(Icons.dynamic_feed),
                    label: 'Feed',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: 'Profile',
                  ),
                ],
              ),
            ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shell/main_shell.dart';

/// Where the end of an auth flow leaves the person.
///
/// Signing in or signing up is a door, not a place: once it has been gone
/// through, the app belongs on Home — the timer, which is what the app is
/// for — with every screen the flow put up taken down behind it. Before
/// this, the flow popped back to the shell and left whatever tab was
/// showing, so creating an account from the Friends gate finished on
/// Profile, looking at the screen that had just turned you away.
///
/// [AuthLanding.back] is the exception, for a flow that opened the door
/// for a destination of its own: it is still standing where it was, so
/// its screen is what the auth screen comes off to reveal.
enum AuthLanding {
  /// Home, with every pushed screen gone. The default, and what a plain
  /// sign-in or sign-up does.
  home,

  /// The screen the flow was opened from, with the rest of the stack
  /// untouched.
  back,
}

/// Home's index in the shell's tabs: 0 Home · 1 Feed · 2 Profile.
const int kHomeTab = 0;

/// The end of an auth flow.
///
/// The tab is set BEFORE the pop, so the shell is already on Home as it is
/// uncovered and no frame of the tab that was showing is drawn.
///
/// [AuthLanding.back] is one pop because the flow is one route: each step
/// of it — the auth screen, the handle, "Who invited you?" — REPLACES the
/// one before, so however deep the flow has gone there is exactly one of
/// its screens on the stack.
void landAfterAuth(BuildContext context, WidgetRef ref, AuthLanding landing) {
  switch (landing) {
    case AuthLanding.home:
      ref.read(selectedTabProvider.notifier).set(kHomeTab);
      Navigator.of(context).popUntil((route) => route.isFirst);
    case AuthLanding.back:
      Navigator.of(context).maybePop();
  }
}

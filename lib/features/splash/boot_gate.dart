import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../habits/habits_providers.dart';
import '../shell/main_shell.dart';
import '../tasks/tasks_providers.dart';

/// Holds a launch splash over the app until Home's data is ready, hiding the
/// empty-state flash (the brief "add a task" / blank rings before the first
/// Firestore fetch resolves).
///
/// Gate: lifts the instant **both** [tasksProvider] and [habitsProvider] reach
/// their first value — no fixed timer on the success path. Safety nets so a
/// dead network can never trap the user: it also lifts if either provider
/// errors, or if [_maxWait] elapses. Latched — shown once on cold start; later
/// provider refreshes (e.g. after adding a task) never bring it back.
class BootGate extends ConsumerStatefulWidget {
  const BootGate({super.key});

  @override
  ConsumerState<BootGate> createState() => _BootGateState();
}

class _BootGateState extends ConsumerState<BootGate> {
  bool _ready = false;
  Timer? _failsafe;

  static const Duration _maxWait = Duration(seconds: 6);
  static const Duration _fade = Duration(milliseconds: 320);

  @override
  void initState() {
    super.initState();
    // Failsafe: never strand the user on the splash if a fetch hangs.
    _failsafe = Timer(_maxWait, _lift);
  }

  @override
  void dispose() {
    _failsafe?.cancel();
    super.dispose();
  }

  void _lift() {
    if (_ready || !mounted) return;
    setState(() => _ready = true);
    _failsafe?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    // Only gate before the latch trips; afterwards we stop watching so later
    // provider refreshes can never re-show the splash.
    if (!_ready) {
      final tasks = ref.watch(tasksProvider);
      final habits = ref.watch(habitsProvider);

      final bothLoaded = tasks.hasValue && habits.hasValue;
      final anyError = tasks.hasError || habits.hasError;
      if (bothLoaded || anyError) {
        // Can't setState during build — lift after this frame.
        WidgetsBinding.instance.addPostFrameCallback((_) => _lift());
      }
    }

    return AnimatedSwitcher(
      duration: _fade,
      child: _ready
          ? const MainShell(key: ValueKey('shell'))
          : const _SplashScreen(key: ValueKey('splash')),
    );
  }
}

/// Minimal launch splash: a centred "Sondr" wordmark on the app background, so
/// it cross-fades cleanly into [MainShell].
class _SplashScreen extends StatelessWidget {
  const _SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    return ColoredBox(
      color: tokens.background,
      child: Center(
        child: Text(
          'Sondr',
          // Exact match to the home "Last 10 days" header (titleLarge → 20/w700,
          // inheriting Inter, letterSpacing -0.2, and the primary colour).
          style: theme.textTheme.titleLarge
              ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

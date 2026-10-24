import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../shared/cached_photo.dart';
import '../friends/friends_repository.dart';
import '../photos/photos_repository.dart';
import '../profile/friend_mirror.dart';
import '../profile/milestone_strip.dart';
import '../profile/public_profile.dart';
import '../habits/habits_providers.dart';
import '../links/invite_link_listener.dart';
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

/// Decode Profile's photos behind the splash: the hero, the strip's tiles
/// and the newest photos its stretches would show. Resolves when they are
/// decoded or when [kBootPrecacheTimeout] has passed, whichever is first —
/// the splash is held for a moment, never for a network.
///
/// A provider so a test can stand in for it.
final bootPrecacheProvider =
    Provider<Future<void> Function(BuildContext, List<String>)>(
  (ref) => (context, urls) => precachePhotosAwait(context, urls)
      .timeout(kBootPrecacheTimeout, onTimeout: () {}),
);
const Duration kBootPrecacheTimeout = Duration(milliseconds: 1500);

class _BootGateState extends ConsumerState<BootGate> {
  bool _ready = false;
  bool _warming = false;
  Timer? _failsafe;

  static const Duration _maxWait = Duration(seconds: 6);
  static const Duration _fade = Duration(milliseconds: 320);

  @override
  void initState() {
    super.initState();
    // Failsafe: never strand the user on the splash if a fetch hangs.
    _failsafe = Timer(_maxWait, _lift);
    // A prune whose writes never reached the server — the app was killed,
    // or it was offline — is finished here. Fire and forget: it must never
    // hold the splash up, and it is retried on every launch until the
    // server confirms it.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(pendingPruneRunnerProvider)());
      // What other people see of us, and the friend mirror their profiles
      // are listed in. Both fire and forget, both idempotent, and both
      // write nothing when there is nothing new to say — the splash must
      // never wait on either.
      unawaited(ref.read(publishPublicProfileProvider)());
      unawaited(ref.read(friendMirrorReconcileProvider)());
    });
  }

  @override
  void dispose() {
    _failsafe?.cancel();
    super.dispose();
  }

  /// Everything Profile paints on its first frame, decoded first. Runs once
  /// the data is in; lifts the splash when the photos are in memory or the
  /// timeout has passed. The failsafe still lifts it regardless.
  Future<void> _warmThenLift(List<String> urls) async {
    if (_warming || !mounted) return;
    _warming = true;
    try {
      await ref.read(bootPrecacheProvider)(context, urls);
    } catch (_) {
      // A decode that failed costs exactly what not asking would have.
    }
    _lift();
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
      // Profile's photos too: the hero and the strip are read local-first,
      // so this is the cache answering, not a network. Their images are
      // then decoded before the splash lifts, so Profile's first frame is
      // complete — nothing lands a moment later.
      final gallery = ref.watch(galleryPreviewProvider);
      final strip = ref.watch(milestoneStripProvider);

      final anyError = tasks.hasError ||
          habits.hasError ||
          gallery.hasError ||
          strip.hasError;
      final allLoaded = tasks.hasValue &&
          habits.hasValue &&
          gallery.hasValue &&
          strip.hasValue;
      if (anyError) {
        // Can't setState during build — lift after this frame.
        WidgetsBinding.instance.addPostFrameCallback((_) => _lift());
      } else if (allLoaded && !_warming) {
        final urls = <String>[
          for (final p in gallery.value!.take(1)) p.photoUrl,
          for (final e in strip.value!) e.photo.photoUrl,
          for (final e in strip.value!)
            for (final p in e.detail.photos) p.photoUrl,
        ];
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _warmThenLift(urls));
      }
    }

    return AnimatedSwitcher(
      duration: _fade,
      // The link listener wraps the shell rather than living inside it, so
      // it starts only once there is a navigator to push onto. A link that
      // launched the app is delivered the moment the splash lifts.
      child: _ready
          ? const InviteLinkListener(
              key: ValueKey('shell'),
              child: MainShell(),
            )
          : const _SplashScreen(key: ValueKey('splash')),
    );
  }
}

/// Minimal launch splash: a centred "sondr" wordmark on the app background, so
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
          'sondr',
          // Exact match to the home "Last 10 days" header (titleLarge → 20/w700,
          // inheriting Inter, letterSpacing -0.2, and the primary colour).
          style: theme.textTheme.titleLarge
              ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

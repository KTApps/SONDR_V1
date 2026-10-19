import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/spacing.dart';
import '../../core/utils/duration_format.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_error.dart';
import '../../shared/sondr_prompt.dart';
import '../photos/auto_collage.dart';
import '../timer/live_activity.dart';
import '../timer/session_clock.dart';
import '../timer/session_store.dart';
import '../timer/timer_controller.dart';
import 'auth_repository.dart';

/// How long to wait for the server to admit it has the time.
///
/// Firestore's write completes when the server acknowledges it, not when
/// it reaches the local cache — so offline it simply never completes.
/// Ten seconds is long enough for a bad connection and short enough that
/// nobody wonders whether the button worked.
const Duration kSignOutSaveTimeout = Duration(seconds: 10);

/// What the prompt says about a session that is about to be stopped.
///
/// Public for the test, which should be able to pin the words without
/// pumping a dialog.
String signOutPromptBody(SessionClock clock, DateTime now) {
  final task = clock.taskName ?? 'Your session';
  final elapsed = DurationFormat.hm(clock.elapsedAt(now));
  return clock.isPaused
      ? '$task is paused at $elapsed. Signing out will stop it and save '
            'the time to this account.'
      : '$task is still running ($elapsed). Signing out will stop it and '
            'save the time to this account.';
}

/// Sign out — and, if a session is running, stop it first.
///
/// Signing out used to take the Lock Screen card away and leave the
/// session running for whoever signed in next: their first glance at Home
/// showed somebody else's timer, and the hours went to the wrong account.
///
/// So the session is stopped and credited to the account that earned it,
/// and the order matters. The time has to be known to have reached the
/// server BEFORE anything is thrown away, because once signed out there
/// is no retrying it. If it cannot be confirmed, nothing happens at all —
/// not the sign-out, not the clearing — and the owner is told why.
class SignOutAction extends ConsumerStatefulWidget {
  const SignOutAction({super.key});

  @override
  ConsumerState<SignOutAction> createState() => _SignOutActionState();
}

class _SignOutActionState extends ConsumerState<SignOutAction> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final scale = figmaScale(context);
    final error = _error;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SondrAction(
          label: _busy ? 'Stopping…' : 'Sign out',
          supporting: true,
          // Null while busy: the save takes as long as the network does,
          // and a second tap would start a second stop.
          onPressed: _busy ? null : _signOut,
        ),
        if (error != null) ...[
          SizedBox(height: kSpacingPair * scale),
          SondrError(error, textAlign: TextAlign.center),
        ],
      ],
    );
  }

  Future<void> _signOut() async {
    final timer = ref.read(timerControllerProvider.notifier);
    // The card may have been paused from the Lock Screen since this
    // process last looked.
    await timer.sync();
    if (!mounted) return;

    final clock = timer.clock;
    if (clock == null) {
      // No session — but a card can still be left over from a launch that
      // was killed mid-session, and it names a task belonging to whoever
      // is leaving. Otherwise: sign out exactly as it always did.
      await ref.read(liveActivityProvider).clear();
      await _signOutNow();
      return;
    }

    final now = ref.read(nowProvider)();
    final stop = await showSondrConfirm(
      context,
      title: 'Stop your session?',
      body: signOutPromptBody(clock, now),
      confirmLabel: 'Stop and sign out',
    );
    if (!stop || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Credit it to the account that earned it, and wait to be told the
      // server has it. No camera, no celebration, no notice — this is a
      // sign-out, not the end of a session someone is standing over.
      final outcome = await timer
          .commitKeepingSession()
          .timeout(kSignOutSaveTimeout);
      if (!mounted) return;
      if (outcome.reachedMilestone && outcome.taskId != null) {
        unawaited(
          autoComposeCollage(ref, outcome.taskId!, outcome.milestoneHours!),
        );
      }
      // Only now: the time is safe, so the session can go. discard()
      // takes the card down itself, which is why the card is not cleared
      // again here.
      await timer.discard();
      if (!mounted) return;
      await _signOutNow();
    } catch (e) {
      debugPrint('SONDR sign-out save error: ${e.runtimeType} :: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error =
            "Couldn't save your session. Check your connection and try again.";
      });
    }
  }

  /// As it has always worked: a fresh guest session, and AccountBody
  /// rebuilds itself into the guest view.
  Future<void> _signOutNow() =>
      ref.read(authRepositoryProvider).signOut();
}

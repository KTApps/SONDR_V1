import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/duration_format.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/sondr_action.dart';
import '../tasks/tasks_providers.dart';
import '../timer/timer_controller.dart';

/// The quietened Focus Mode surface, shown in place of the home screen while a
/// focused session runs. Everything is stripped away but the task, the live
/// session time, and pause/stop — the user is "locked into the effort" and only
/// touches the app to break or finish. Leaving Focus happens by stopping
/// (handled by [onStop], which also commits the session and celebrates a
/// milestone if one was crossed).
///
/// There is no "FOCUS" heading: the bare screen, the task name and the running
/// clock already say what this is, and a label would only restate it.
class FocusView extends ConsumerWidget {
  const FocusView({super.key, required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final task = ref.watch(selectedTaskProvider);
    final timer = ref.watch(timerControllerProvider);
    final controller = ref.read(timerControllerProvider.notifier);
    final isRunning = timer.status == TimerStatus.running;
    final gap = SizedBox(height: kSpacingSection * scale);
    // Empty when the selected task is deleted mid-session. The heading and
    // its gap both go, rather than leaving a blank line and 24pt of nothing
    // above the clock.
    final name = task?.name ?? '';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: kSpacingSection * scale),
          // Full width, explicitly. A Column sizes its cross axis to its
          // widest child, and every child here is centred text or a
          // MainAxisSize.min row — so without this the column shrink-wraps
          // the clock and the whole screen sits left of centre.
          child: SizedBox(
            width: double.infinity,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (name.isNotEmpty) ...[
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    // Two lines then ellipsis: the page is centred and does not
                    // scroll, so an unbounded name would push the clock and the
                    // controls off their own screen.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 20 * scale,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                  gap,
                ],

                // The live session time — the whole point of the screen, and the
                // only thing on it allowed to be this large.
                // Shrinks rather than overflows: past 100 hours the string
                // grows a digit and 44pt no longer fits the width.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    DurationFormat.stopwatch(timer.sessionElapsed),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 44 * scale,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                SizedBox(height: kSpacingBase * scale),

                // Supporting text, so it is grey — it says what the clock is
                // doing, it is not something to tap.
                Text(
                  isRunning ? 'in session' : 'paused',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w700,
                    color: tokens.textSecondary,
                  ),
                ),
                gap,

                SondrActionPair(
                  firstLabel: isRunning ? 'Pause' : 'Resume',
                  onFirst: isRunning ? controller.pause : controller.start,
                  secondLabel: 'Stop',
                  onSecond: onStop,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
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

  /// One spacing unit, used for every gap on the screen (see DESIGN.md).
  static const double _spacing = 24;

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
    final gap = SizedBox(height: _spacing * scale);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: _spacing * scale),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                task?.name ?? '',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 20 * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              gap,

              // The live session time — the whole point of the screen, and the
              // only thing on it allowed to be this large.
              Text(
                DurationFormat.stopwatch(timer.sessionElapsed),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 44 * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              SizedBox(height: _spacing * scale / 2),

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

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SondrAction(
                    label: isRunning ? 'Pause' : 'Resume',
                    onPressed: isRunning ? controller.pause : controller.start,
                  ),
                  SizedBox(width: _spacing * scale),
                  SondrAction(label: 'Stop', onPressed: onStop),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

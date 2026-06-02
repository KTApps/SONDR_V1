import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/duration_format.dart';
import '../tasks/tasks_providers.dart';
import '../timer/timer_controller.dart';

/// The quietened Focus Mode surface, shown in place of the home screen while a
/// focused session runs. Everything is stripped away but the task, the live
/// session time, and pause/stop — the user is "locked into the effort" and only
/// touches the app to break or finish. Leaving Focus happens by stopping
/// (handled by [onStop], which also commits the session and celebrates a
/// milestone if one was crossed).
class FocusView extends ConsumerWidget {
  const FocusView({super.key, required this.onStop});

  final VoidCallback onStop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final task = ref.watch(selectedTaskProvider);
    final timer = ref.watch(timerControllerProvider);
    final controller = ref.read(timerControllerProvider.notifier);
    final isRunning = timer.status == TimerStatus.running;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'FOCUS',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: tokens.textTertiary,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 16),
              Text(task?.name ?? '', style: theme.textTheme.titleLarge),
              const SizedBox(height: 40),

              // The live session time — the whole point of the screen.
              Text(
                DurationFormat.stopwatch(timer.sessionElapsed),
                style: theme.textTheme.displayLarge,
              ),
              const SizedBox(height: 8),
              Text(
                isRunning ? 'in session' : 'paused',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: tokens.textSecondary),
              ),
              const SizedBox(height: 56),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _FocusButton(
                    filled: false,
                    icon: isRunning
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    label: isRunning ? 'Pause' : 'Resume',
                    onPressed: isRunning ? controller.pause : controller.start,
                  ),
                  const SizedBox(width: 16),
                  _FocusButton(
                    filled: true,
                    icon: Icons.stop_rounded,
                    label: 'Stop',
                    onPressed: onStop,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusButton extends StatelessWidget {
  const _FocusButton({
    required this.filled,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final bool filled;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
    const padding = EdgeInsets.symmetric(horizontal: 26, vertical: 16);
    final textStyle = Theme.of(context).textTheme.labelLarge;

    if (filled) {
      return ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: tokens.ringFillOuter,
          foregroundColor: tokens.background,
          elevation: 0,
          padding: padding,
          shape: shape,
          textStyle: textStyle,
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.textPrimary,
        side: BorderSide(color: tokens.ringTrack),
        padding: padding,
        shape: shape,
        textStyle: textStyle,
      ),
    );
  }
}

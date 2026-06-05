import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/date.dart';
import '../../core/utils/duration_format.dart';
import '../../shared/ring/mini_ring.dart';
import '../../shared/ring/ring_dial.dart';
import '../focus/focus_providers.dart';
import '../focus/focus_view.dart';
import '../habits/habits_overlay.dart';
import '../habits/habits_providers.dart';
import '../history/calendar_screen.dart';
import '../milestone/milestone_celebration.dart';
import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';
import 'centre_period.dart';
import 'timer_controller.dart';
import 'widgets/task_dropdown.dart';

/// The home / timer screen — Sondr's main surface.
///
/// The outer ring is a pie of how today's time is split across tasks; the inner
/// ring is today's habits. The task dropdown drives two modes: collective
/// "Task" overview (centre = total across all tasks, view-only) and a specific
/// task (centre follows it, timer controls appear). Swiping the centre toggles
/// the figure between today and this month. Milestone progress lives only in
/// the dropdown bars, never here.
class TimerScreen extends ConsumerWidget {
  const TimerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final now = DateTime.now();

    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final selectedId = ref.watch(selectedTaskIdProvider);
    final selectedTask = ref.watch(selectedTaskProvider);
    final timer = ref.watch(timerControllerProvider);
    final habitProgress = ref.watch(habitsTodayProgressProvider);
    final period = ref.watch(centrePeriodProvider);

    // Focus Mode replaces the whole home with the quietened focused view.
    if (ref.watch(focusModeProvider)) {
      return FocusView(onStop: () => _onStop(context, ref, selectedTask));
    }

    final isCollective = selectedTask == null;
    final liveSeconds = timer.sessionElapsed.inSeconds;

    // The outer ring is always today's split. The in-progress session is folded
    // into the selected task's slice so it grows live while the timer runs.
    final segments = <double>[
      for (final t in tasks)
        (t.todaySeconds(now) + (t.id == selectedId ? liveSeconds : 0)).toDouble(),
    ];
    final highlightIndex = selectedTask == null
        ? null
        : _indexOrNull(tasks.indexWhere((t) => t.id == selectedTask.id));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        // Account & friends/milestones now live in the Profile tab (step 2);
        // the timer is the Home tab and carries no top-right actions.
        title: const Text('Sondr'),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 4),
              const Center(child: TaskDropdown()),
              const SizedBox(height: 28),

              // --- The hero dial. Swipe the centre to toggle today/month. ---
              RingDial(
                taskSegments: segments,
                highlightedSegment: highlightIndex,
                habitProgress: habitProgress,
                size: 300,
                onInnerRingTap: () => showHabitsOverlay(context),
                center: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragEnd: (_) =>
                      ref.read(centrePeriodProvider.notifier).toggle(),
                  child: _DialCentre(
                    tasks: tasks,
                    selectedTask: selectedTask,
                    isCollective: isCollective,
                    timer: timer,
                    period: period,
                    now: now,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _PeriodDots(period: period),
              const SizedBox(height: 28),

              // --- Controls: only a specific task can run a session. ---
              if (isCollective)
                _CollectiveHint(hasTasks: tasks.isNotEmpty)
              else
                _TimerControls(
                  timer: timer,
                  onStart: () => _onStartPressed(context, ref),
                  onResume: () =>
                      ref.read(timerControllerProvider.notifier).start(),
                  onPause: () =>
                      ref.read(timerControllerProvider.notifier).pause(),
                  onStop: () => _onStop(context, ref, selectedTask),
                ),
              const SizedBox(height: 36),

              // --- Last 10 days: each ring is that day's task split. ---
              _SectionLabel('Last 10 days'),
              const SizedBox(height: 14),
              _LastTenDays(
                tasks: tasks,
                selectedId: selectedId,
                liveSeconds: liveSeconds,
                now: now,
              ),
              const SizedBox(height: 28),

              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CalendarScreen()),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: tokens.textPrimary,
                  side: BorderSide(color: tokens.ringTrack),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text('View your progress',
                    style: theme.textTheme.labelLarge),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  int? _indexOrNull(int i) => i < 0 ? null : i;

  /// Pressing Start on a fresh (idle) session offers Focus Mode first, then
  /// starts. Resuming a paused session doesn't re-prompt.
  Future<void> _onStartPressed(BuildContext context, WidgetRef ref) async {
    final tokens = GreyscaleTokens.of(context);
    final enableFocus = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: tokens.surface,
        title: const Text('Focus mode'),
        content: const Text(
          'Lock into this task — the app quietens to just pause and stop until '
          'you finish.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    ref.read(timerControllerProvider.notifier).start();
    if (enableFocus == true) {
      ref.read(focusModeProvider.notifier).enable();
    }
  }

  Future<void> _onStop(
      BuildContext context, WidgetRef ref, Task? task) async {
    final outcome = await ref.read(timerControllerProvider.notifier).stop();
    // Always leave Focus Mode when the session ends.
    ref.read(focusModeProvider.notifier).disable();
    if (!context.mounted || outcome.loggedSeconds <= 0) return;

    // Crossing a 20-hour boundary takes over with the celebration moment;
    // otherwise just confirm the logged time.
    if (outcome.reachedMilestone) {
      await showMilestoneCelebration(
        context,
        taskName: outcome.taskName ?? 'task',
        milestoneHours: outcome.milestoneHours!,
        isFirst: outcome.isFirstMilestone,
      );
      return;
    }

    final logged = DurationFormat.hm(Duration(seconds: outcome.loggedSeconds));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
          SnackBar(content: Text('Logged $logged to ${outcome.taskName}')));
  }

}

/// Centre of the dial. While a specific task's session runs, the live stopwatch
/// is the hero; otherwise the figure is the chosen window (today / this month)
/// — for the selected task, or the total across all tasks in collective mode.
class _DialCentre extends StatelessWidget {
  const _DialCentre({
    required this.tasks,
    required this.selectedTask,
    required this.isCollective,
    required this.timer,
    required this.period,
    required this.now,
  });

  final List<Task> tasks;
  final Task? selectedTask;
  final bool isCollective;
  final TimerState timer;
  final CentrePeriod period;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    final String value;
    final String label = period == CentrePeriod.today ? 'today' : 'this month';

    if (tasks.isEmpty) {
      return _centreColumn(theme, tokens, '—', 'add a task');
    }

    // Seconds for the active window.
    final int seconds;
    if (isCollective) {
      seconds = tasks.fold<int>(
        0,
        (sum, t) => sum +
            (period == CentrePeriod.today
                ? t.todaySeconds(now)
                : t.monthSeconds(now)),
      );
    } else {
      // Fold the live session into the selected task's totals.
      final live = selectedTask!.addingSeconds(timer.sessionElapsed.inSeconds, now);
      seconds = period == CentrePeriod.today
          ? live.todaySeconds(now)
          : live.monthSeconds(now);
    }

    final duration = Duration(seconds: seconds);
    // Running → tick with seconds precision; otherwise the rounded h/m figure.
    value = timer.isRunning
        ? DurationFormat.stopwatch(duration)
        : DurationFormat.hm(duration);

    return _centreColumn(theme, tokens, value, label);
  }

  Widget _centreColumn(
    ThemeData theme,
    GreyscaleTokens tokens,
    String value,
    String label,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: theme.textTheme.displayMedium),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.labelMedium
              ?.copyWith(color: tokens.textSecondary),
        ),
      ],
    );
  }
}

/// Two-dot affordance under the dial hinting the today⟷month centre swipe.
class _PeriodDots extends StatelessWidget {
  const _PeriodDots({required this.period});
  final CentrePeriod period;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    Widget dot(bool active) => Container(
          width: 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? tokens.ringFillOuter : tokens.ringTrack,
          ),
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        dot(period == CentrePeriod.today),
        dot(period == CentrePeriod.month),
      ],
    );
  }
}

/// Shown in collective mode, where there is no session to run.
class _CollectiveHint extends StatelessWidget {
  const _CollectiveHint({required this.hasTasks});
  final bool hasTasks;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final text = hasTasks
        ? 'Pick a task to start a session'
        : 'Add a task to start tracking';
    return SizedBox(
      height: 56,
      child: Center(
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: tokens.textTertiary),
        ),
      ),
    );
  }
}

class _TimerControls extends StatelessWidget {
  const _TimerControls({
    required this.timer,
    required this.onStart,
    required this.onResume,
    required this.onPause,
    required this.onStop,
  });

  final TimerState timer;

  /// Fresh start (idle) — offers Focus Mode.
  final VoidCallback onStart;

  /// Resume from pause — no Focus prompt.
  final VoidCallback onResume;
  final VoidCallback onPause;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    switch (timer.status) {
      case TimerStatus.idle:
        return _PrimaryControl(
          icon: Icons.play_arrow_rounded,
          label: 'Start',
          onPressed: onStart,
        );
      case TimerStatus.running:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SecondaryControl(
                icon: Icons.pause_rounded, label: 'Pause', onPressed: onPause),
            const SizedBox(width: 16),
            _PrimaryControl(
                icon: Icons.stop_rounded, label: 'Stop', onPressed: onStop),
          ],
        );
      case TimerStatus.paused:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _SecondaryControl(
                icon: Icons.play_arrow_rounded,
                label: 'Resume',
                onPressed: onResume),
            const SizedBox(width: 16),
            _PrimaryControl(
                icon: Icons.stop_rounded, label: 'Stop', onPressed: onStop),
          ],
        );
    }
  }
}

/// Filled greyscale action button (fill tone background, surface-tone glyph).
class _PrimaryControl extends StatelessWidget {
  const _PrimaryControl({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: tokens.ringFillOuter,
        foregroundColor: tokens.background,
        disabledBackgroundColor: tokens.ringTrack,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

/// Outlined greyscale action button.
class _SecondaryControl extends StatelessWidget {
  const _SecondaryControl({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.textPrimary,
        side: BorderSide(color: tokens.ringTrack),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: Theme.of(context).textTheme.labelLarge,
      ),
    );
  }
}

class _LastTenDays extends StatelessWidget {
  const _LastTenDays({
    required this.tasks,
    required this.selectedId,
    required this.liveSeconds,
    required this.now,
  });

  final List<Task> tasks;
  final String? selectedId;
  final int liveSeconds;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final keys = DayKey.lastDays(10, now);
    final today = DayKey.of(now);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final key in keys)
          MiniRing(
            size: 26,
            segments: [
              for (final t in tasks)
                ((t.secondsByDay[key] ?? 0) +
                        (key == today && t.id == selectedId ? liveSeconds : 0))
                    .toDouble(),
            ],
          ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

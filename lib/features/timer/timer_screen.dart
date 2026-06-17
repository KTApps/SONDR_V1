import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug_flags.dart';
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Responsive dial: take a share of the available height, capped, so
            // the whole screen fits statically (no scroll) on any phone while
            // the ring stays the hero. It only shrinks when space is tight.
            final dialSize = (constraints.maxHeight * 0.35).clamp(190.0, 265.0);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  const Center(child: TaskDropdown()),
                  const SizedBox(height: 16),

                  // --- The hero dial. Swipe the centre to toggle today/month. ---
                  RingDial(
                    taskSegments: segments,
                    highlightedSegment: highlightIndex,
                    habitProgress: habitProgress,
                    size: dialSize,
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
                  const SizedBox(height: 12),
                  _PeriodDots(period: period),
                  const SizedBox(height: 18),

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

                  // Dev-only: push the selected task to just below its first 20h
                  // milestone so a short session crosses it (DEBUG_TOOLS only).
                  if (kDebugTools && selectedTask != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () =>
                          _primeMilestone(context, ref, selectedTask),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: tokens.textTertiary,
                        side: BorderSide(color: tokens.ringTrack),
                      ),
                      child: const Text('DEBUG · prime to milestone edge'),
                    ),
                  ],

                  // Most of the slack goes below the block, so the whole group
                  // rises into the empty space just under the hint while a
                  // comfortable gap remains above the tab bar (never touching).
                  const Spacer(flex: 1),

                  // --- Last 10 days: minimal grid of mini dual-rings on the
                  // plain background, with a "View your progress" text CTA. ---
                  _LastTenDays(now: now),
                  const Spacer(flex: 2),
                ],
              ),
            );
          },
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
        totalHours: outcome.totalHours,
        isFirst: outcome.isFirstMilestone,
        // For now only the first 20h milestone offers a post; the widening
        // milestone ladder (and posting on later rungs) is a separate step.
        canShare: outcome.isFirstMilestone,
      );
      return;
    }

    final logged = DurationFormat.hm(Duration(seconds: outcome.loggedSeconds));
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
          SnackBar(content: Text('Logged $logged to ${outcome.taskName}')));
  }

  /// DEBUG_TOOLS only: log enough time to leave [task] ~90s below its first 20h
  /// milestone, so a short live session crosses it and exercises the real
  /// milestone → post → feed loop.
  void _primeMilestone(BuildContext context, WidgetRef ref, Task task) {
    final edgeSeconds = Task.milestoneStepHours * 3600 - 90;
    final needed = edgeSeconds - task.totalSeconds;
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    if (needed <= 0) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Already at/past the first milestone')));
      return;
    }
    ref.read(tasksProvider.notifier).logSeconds(task.id, needed, DateTime.now());
    messenger.showSnackBar(SnackBar(
        content: Text(
            'Primed ${task.name} near 20h — run a short session to cross')));
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

/// The "Last 10 days" module: a label, two rows of five mini dual-rings, and a
/// plain-text "View your progress" CTA, all sitting directly on the background
/// (no border, no panel). Each cell mirrors the hero dial at small scale —
/// outer ring = that day's task split, inner ring = that day's habits — with a
/// days-ago number in the centre. Today is excluded (it's the big dial above):
/// the grid reads 1 (yesterday) at top-left across to 10 (oldest) at
/// bottom-right. The day circles are display-only; only the CTA navigates.
class _LastTenDays extends ConsumerWidget {
  const _LastTenDays({required this.now});

  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final habitsState = ref.watch(habitsProvider).value;
    final today = DateTime(now.year, now.month, now.day);

    Widget cell(int daysAgo) {
      final key = DayKey.of(today.subtract(Duration(days: daysAgo)));
      final segments = <double>[
        for (final t in tasks) (t.secondsByDay[key] ?? 0).toDouble(),
      ];
      // 0 (or no record) renders only the faint inner track — never a fill.
      final habitProgress = habitsState?.days[key]?.progress ?? 0.0;
      return MiniRing(
        size: 46,
        segments: segments,
        habitProgress: habitProgress,
        child: Text(
          '$daysAgo',
          style: theme.textTheme.labelSmall?.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    Widget row(Iterable<int> daysAgo) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [for (final d in daysAgo) cell(d)],
        );

    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Last 10 days', style: theme.textTheme.titleMedium),
          // Top gap (label → first row) matches the bottom gap (last row → CTA).
          const SizedBox(height: 22),
          row(const [1, 2, 3, 4, 5]),
          const SizedBox(height: 10),
          row(const [6, 7, 8, 9, 10]),
          // A touch more separation here drops the CTA slightly lower than the
          // label→first-row gap, using the space above the tab bar.
          const SizedBox(height: 30),

          // Plain-text CTA; opens the calendar/progress screen (same
          // destination the standalone button used to). The day circles
          // themselves stay display-only.
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CalendarScreen()),
            ),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                'View your progress',
                textAlign: TextAlign.center,
                // Same size as the "Last 10 days" label (titleMedium), white.
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: tokens.textPrimary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

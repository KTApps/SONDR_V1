import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug_flags.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/date.dart';
import '../../core/utils/duration_format.dart';
import '../../shared/ring/segmented_dial.dart';
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
    final todayHabits = ref.watch(todayHabitsProvider);
    final habitStates = <bool>[
      for (final t in todayHabits?.ticks ?? const []) t.done,
    ];
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
      // Absolute layout matching the Figma's measured positions on the 393x852
      // reference (no AppBar/SafeArea, so coordinates are screen-global). Dial
      // size/position here is layout only — ring rendering is untouched.
      body: Stack(
        children: [
          // "Sondr" — Inter Bold 15.
          Positioned(
            top: 30,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Sondr',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          // Task selector — nudged down slightly to tighten the gap to the dial.
          const Positioned(
            top: 102,
            left: 0,
            right: 0,
            child: Center(child: TaskDropdown()),
          ),
          // Hero dial. Swipe the centre to toggle today/month. Its top sits
          // below the open dropdown's top (146) and its bottom (412) above the
          // period dots (421), so the open dropdown fully covers it.
          Positioned(
            top: 152,
            left: 0,
            right: 0,
            child: Center(
              child: SegmentedDial(
                taskTodaySeconds: segments,
                selectedTaskIndex: highlightIndex,
                habitStates: habitStates,
                size: 260,
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
            ),
          ),
          // Period dots (today⟷month swipe affordance).
          Positioned(
            top: 421,
            left: 0,
            right: 0,
            child: Center(child: _PeriodDots(period: period)),
          ),
          // Control: collective hint, or the running/paused timer controls.
          Positioned(
            top: 444,
            left: 0,
            right: 0,
            child: Center(
              child: isCollective
                  ? _CollectiveHint(hasTasks: tasks.isNotEmpty)
                  : _TimerControls(
                      timer: timer,
                      onStart: () => _onStartPressed(context, ref),
                      onResume: () =>
                          ref.read(timerControllerProvider.notifier).start(),
                      onPause: () =>
                          ref.read(timerControllerProvider.notifier).pause(),
                      onStop: () => _onStop(context, ref, selectedTask),
                    ),
            ),
          ),
          // "Last 10 days" block — Figma Y positions, shifted up with the stack.
          Positioned(
            top: 511,
            left: 24,
            right: 24,
            child: _LastTenDays(now: now),
          ),
          // Dev-only milestone primer (DEBUG_TOOLS builds only; off by default).
          if (kDebugTools && selectedTask != null)
            Positioned(
              top: 116,
              left: 24,
              right: 24,
              child: Center(
                child: OutlinedButton(
                  onPressed: () => _primeMilestone(context, ref, selectedTask),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: tokens.textTertiary,
                    side: BorderSide(color: tokens.ringTrack),
                  ),
                  child: const Text('DEBUG · prime to milestone edge'),
                ),
              ),
            ),
        ],
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
        Text(
          value,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: tokens.textSecondary,
          ),
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
      // That day's habits as per-habit done/not-done segments (empty list →
      // solid empty inner ring), matching the main dial.
      final habitStates = <bool>[
        for (final tick in habitsState?.days[key]?.ticks ?? const []) tick.done,
      ];
      return SegmentedDial(
        size: 57,
        compact: true,
        taskTodaySeconds: segments,
        habitStates: habitStates,
        center: Text(
          '$daysAgo',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: tokens.textSecondary,
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
          Text(
            'Last 10 days',
            style: theme.textTheme.titleLarge
                ?.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          // Exact Figma pitch: label→row1 30, row1→row2 25, row2→CTA 42
          // (with 46px rows this lands the rows at Y599 / Y670 and CTA at Y758).
          const SizedBox(height: 30),
          row(const [1, 2, 3, 4, 5]),
          const SizedBox(height: 25),
          row(const [6, 7, 8, 9, 10]),
          const SizedBox(height: 42),

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
                // Bold 15 — deliberately smaller than the Bold 20 section label.
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

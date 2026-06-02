import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import 'habits_providers.dart';
import 'models/daily_habits.dart';

/// Presents the daily-habits panel as a frosted blur over the current screen:
/// the main screen stays visible, blurred behind a dark greyscale scrim, with
/// the habit content floating centred on top. Tapping the blurred area or
/// swiping/back dismisses it.
Future<void> showHabitsOverlay(BuildContext context) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 200),
      reverseTransitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (_, _, _) => const HabitsOverlay(),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

/// The frosted habits panel. Shows only today's list (no day browsing): the
/// weekday, date, day streak, the centred habit names (tap to toggle, swipe to
/// remove), and "Add habit" at the bottom.
class HabitsOverlay extends ConsumerWidget {
  const HabitsOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final today = ref.watch(todayHabitsProvider);
    final streak = ref.watch(habitStreakProvider);
    final now = DateTime.now();

    return Stack(
      children: [
        // Frosted backdrop — blurs the main screen behind; tap to dismiss.
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: ColoredBox(
                color: tokens.background.withValues(alpha: 0.55),
              ),
            ),
          ),
        ),

        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_weekday(now.weekday),
                      style: theme.textTheme.displayMedium),
                  const SizedBox(height: 4),
                  Text('${now.day} ${_month(now.month)}',
                      style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 16),
                  _StreakBadge(streak: streak),
                  const SizedBox(height: 32),

                  if (today != null)
                    for (final tick in today.ticks)
                      _HabitNameRow(
                        key: ValueKey(tick.habitId),
                        tick: tick,
                        onToggle: () => ref
                            .read(habitsProvider.notifier)
                            .toggle(tick.habitId),
                        onRemove: () =>
                            ref.read(habitsProvider.notifier).removeHabit(tick.habitId),
                      ),

                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => _promptAddHabit(context, ref),
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.textPrimary,
                      textStyle: theme.textTheme.labelLarge,
                    ),
                    child: const Text('Add habit'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _promptAddHabit(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final tokens = GreyscaleTokens.of(context);

    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: tokens.surface,
          title: const Text('Add habit'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'e.g. Cold shower'),
            onSubmitted: (v) => Navigator.of(context).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    await ref.read(habitsProvider.notifier).addHabit(trimmed);
  }

  static String _weekday(int w) => const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday',
      ][w - 1];

  static String _month(int m) => const [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December',
      ][m - 1];
}

/// The day-streak readout, greyscale.
class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.streak});
  final int streak;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final text = streak == 0 ? 'No streak yet' : '$streak-day streak';
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .titleMedium
          ?.copyWith(color: tokens.textSecondary),
    );
  }
}

/// A centred habit name: tap toggles complete (strike-through), swipe removes.
/// No checkbox or leading circle — the name itself is the control.
class _HabitNameRow extends StatelessWidget {
  const _HabitNameRow({
    super.key,
    required this.tick,
    required this.onToggle,
    required this.onRemove,
  });

  final HabitTick tick;
  final VoidCallback onToggle;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    return Dismissible(
      key: ValueKey('dismiss_${tick.habitId}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => onRemove(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            tick.name,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              color: tick.done ? tokens.textTertiary : tokens.textPrimary,
              decoration: tick.done ? TextDecoration.lineThrough : null,
              decorationColor: tokens.textTertiary,
              decorationThickness: 2,
            ),
          ),
        ),
      ),
    );
  }
}

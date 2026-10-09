import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/date.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/ring/segmented_dial.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_prompt.dart';
import '../../shared/sondr_swipe_row.dart';
import 'habits_providers.dart';
import 'models/daily_habits.dart';

/// Opens today's habits as a full page.
///
/// A page, not a sheet: there is no frosted blur and no grab handle, because
/// this is somewhere you go rather than something that interrupts you. It is
/// reached by tapping the habits band inside the home dial, and leaves by the
/// Back at its foot.
Future<void> showHabitsScreen(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const HabitsScreen()),
  );
}

/// Today's habits: the day, the habits band as a summary, the list, and the
/// two quiet actions at the foot.
///
/// The day is the title because the list only ever shows today — a "Habits"
/// label over a page of habits is a word the screen already says, and so is
/// "N of M today" over a ring that shows exactly that.
class HabitsScreen extends ConsumerWidget {
  const HabitsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final today = ref.watch(todayHabitsProvider);
    final ticks = today?.ticks ?? const <HabitTick>[];
    final now = DateTime.now();

    return Scaffold(
      // SafeArea, so the day clears the notch without a sheet's chrome.
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 24 * scale,
            vertical: kSpacingBase * scale,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          DayKey.weekday(now.weekday),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 20 * scale,
                            fontWeight: FontWeight.w700,
                            color: tokens.textPrimary,
                          ),
                        ),
                        SizedBox(height: kSpacingPair * scale),
                        Text(
                          '${now.day} ${DayKey.monthName(now.month)}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 13 * scale,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // The same band the dials carry: one arc per habit, white
                  // where it is done. Ticking a row here fills a segment on
                  // Home at the same moment, because both read one state.
                  HabitsRing(
                    size: 44 * scale,
                    states: [for (final t in ticks) t.done],
                  ),
                ],
              ),
              SizedBox(height: kSpacingSection * scale),
              Expanded(
                child: ticks.isEmpty
                    ? Text(
                        'No habits yet.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13 * scale,
                          color: tokens.textSecondary,
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: ticks.length,
                        separatorBuilder: (_, _) => SizedBox(
                          height: 1,
                          child: ColoredBox(color: tokens.ringTrack),
                        ),
                        itemBuilder: (context, i) {
                          final tick = ticks[i];
                          return SondrSwipeRow(
                            key: ValueKey(tick.habitId),
                            actions: [
                              SondrAction(
                                label: 'Remove',
                                fontSize: kRowActionSize,
                                onPressed: () => ref
                                    .read(habitsProvider.notifier)
                                    .removeHabit(tick.habitId),
                              ),
                            ],
                            child: _HabitRow(tick: tick),
                          );
                        },
                      ),
              ),
              // Two quiet actions, stacked. No gap declared between them:
              // SondrAction's own 12 either side meets at 24, the stacked
              // floor (DESIGN.md).
              Center(
                child: SondrAction(
                  label: 'Add habit',
                  supporting: true,
                  onPressed: () => _promptAddHabit(context, ref),
                ),
              ),
              Center(
                child: SondrAction(
                  label: 'Back',
                  supporting: true,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _promptAddHabit(BuildContext context, WidgetRef ref) async {
    final name = await showSondrPrompt(
      context,
      title: 'Add habit',
      confirmLabel: 'Add',
    );
    if (name == null) return;
    await ref.read(habitsProvider.notifier).addHabit(name);
  }
}

/// One habit. The NAME is the control and the state: tertiary grey and regular
/// while it is outstanding, secondary grey and bold once it is done.
///
/// Completing it brightens the name by exactly one step on the ladder, which
/// is the whole move — no white, because white is a milestone reached and a
/// habit is not one, and no jump to the dial's fill grey, which is pitched for
/// a thin arc rather than for a word you have to read.
///
/// No circle, no checkbox, no strike-through. A checkbox is a second thing to
/// read on a row that already says everything, and a struck-out name reads as
/// cancelled rather than as finished.
class _HabitRow extends ConsumerWidget {
  const _HabitRow({required this.tick});

  final HabitTick tick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final streak = ref.watch(habitStreakForProvider(tick.habitId));

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(habitsProvider.notifier).toggle(tick.habitId),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: kSpacingBase * scale),
        child: Row(
          children: [
            Expanded(
              child: Text(
                tick.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15 * scale,
                  fontWeight: tick.done ? FontWeight.w700 : FontWeight.w400,
                  // One step UP the ladder on completion: tertiary while it is
                  // outstanding, secondary once it is done. Never white —
                  // white is a milestone reached, and never the dial's fill
                  // grey either, which is a tone for a 3pt arc rather than for
                  // a name you have to read.
                  color: tick.done ? tokens.textSecondary : tokens.textTertiary,
                ),
              ),
            ),
            // The run of days behind this habit, as metadata. Nothing at all
            // on a habit that has not strung two days together yet.
            if (streak > 0)
              Text(
                '$streak',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

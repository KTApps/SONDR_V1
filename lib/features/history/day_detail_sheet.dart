import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/date.dart';
import '../../core/utils/duration_format.dart';
import '../../shared/ring/ring_dial.dart';
import 'history_providers.dart';

/// Shows a day's detail as a bottom sheet: the date, that day's dual ring
/// (task split + habit completion), the time logged per task, and the habit
/// snapshot. Read-only — history is a record of what was true then.
Future<void> showDayDetailSheet(BuildContext context, String dayKey) {
  final tokens = GreyscaleTokens.of(context);
  return showModalBottomSheet(
    context: context,
    backgroundColor: tokens.surface,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => DayDetailSheet(dayKey: dayKey),
  );
}

class DayDetailSheet extends ConsumerWidget {
  const DayDetailSheet({super.key, required this.dayKey});

  final String dayKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final history = ref.watch(dayHistoryProvider(dayKey));
    final date = DayKey.parse(dayKey);
    final habits = history.habits;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                '${DayKey.weekday(date.weekday)}, '
                '${date.day} ${DayKey.monthName(date.month)}',
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 20),

            // The day's dual ring, static.
            Center(
              child: RingDial(
                taskSegments: history.segments,
                habitProgress: habits?.progress ?? 0.0,
                size: 200,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DurationFormat.hm(
                          Duration(seconds: history.totalSeconds)),
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 2),
                    Text('logged',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: tokens.textSecondary)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            if (!history.hasData)
              _Muted('Nothing tracked on this day')
            else ...[
              if (history.taskTimes.isNotEmpty) ...[
                _SectionLabel('Time per task'),
                const SizedBox(height: 8),
                for (final t in history.taskTimes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                            child: Text(t.name,
                                style: theme.textTheme.bodyLarge)),
                        Text(
                          DurationFormat.hm(Duration(seconds: t.seconds)),
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              if (habits != null && habits.total > 0) ...[
                _SectionLabel('Habits · ${habits.completed} of ${habits.total}'),
                const SizedBox(height: 8),
                for (final tick in habits.ticks)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      tick.name,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: tick.done
                            ? tokens.textTertiary
                            : tokens.textPrimary,
                        decoration:
                            tick.done ? TextDecoration.lineThrough : null,
                        decorationColor: tokens.textTertiary,
                      ),
                    ),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleMedium);
  }
}

class _Muted extends StatelessWidget {
  const _Muted(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: tokens.textTertiary)),
      ),
    );
  }
}

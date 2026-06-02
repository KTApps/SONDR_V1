import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import 'habits_providers.dart';
import 'models/daily_habits.dart';

/// Today's daily-habits checklist. Tap a row to check it off (strike-through),
/// "+" to add a habit, swipe a row to remove it. Editing the list applies from
/// today forward — past days keep their own frozen snapshot (immutable
/// history), so this screen only ever edits today.
class HabitsChecklistScreen extends ConsumerWidget {
  const HabitsChecklistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = ref.watch(todayHabitsProvider);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Daily habits'),
        actions: [
          IconButton(
            tooltip: 'Add habit',
            icon: const Icon(Icons.add),
            onPressed: () => _promptAddHabit(context, ref),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          children: [
            const SizedBox(height: 4),
            Text(_weekday(now.weekday), style: theme.textTheme.headlineMedium),
            const SizedBox(height: 2),
            Text(
              '${now.day} ${_month(now.month)}'
              '${today == null ? '' : '  ·  ${today.completed} of ${today.total} done'}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            if (today == null || today.ticks.isEmpty)
              _EmptyState(onAdd: () => _promptAddHabit(context, ref))
            else
              for (final tick in today.ticks)
                _HabitRow(
                  key: ValueKey(tick.habitId),
                  tick: tick,
                  onToggle: () =>
                      ref.read(habitsProvider.notifier).toggle(tick.habitId),
                  onRemove: () => _removeHabit(context, ref, tick),
                ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _removeHabit(
    BuildContext context,
    WidgetRef ref,
    HabitTick tick,
  ) async {
    await ref.read(habitsProvider.notifier).removeHabit(tick.habitId);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('Removed ${tick.name}')));
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

/// A single habit row: a check disc + label, struck through when done. Swipe
/// to remove.
class _HabitRow extends StatelessWidget {
  const _HabitRow({
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
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onRemove(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 8),
        child: Icon(Icons.delete_outline, color: tokens.textSecondary),
      ),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              _CheckDisc(done: tick.done),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  tick.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: tick.done ? tokens.textTertiary : tokens.textPrimary,
                    decoration:
                        tick.done ? TextDecoration.lineThrough : null,
                    decorationColor: tokens.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Greyscale completion disc: filled with a check when done, hollow otherwise.
class _CheckDisc extends StatelessWidget {
  const _CheckDisc({required this.done});
  final bool done;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? tokens.ringFillOuter : Colors.transparent,
        border: done ? null : Border.all(color: tokens.ringTrack, width: 2),
      ),
      child: done
          ? Icon(Icons.check, size: 16, color: tokens.background)
          : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: Column(
        children: [
          Text(
            'No habits yet',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(color: tokens.textSecondary),
          ),
          const SizedBox(height: 8),
          Text(
            'Add one to start your daily checklist',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: tokens.textTertiary),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 20),
            label: const Text('Add habit'),
            style: OutlinedButton.styleFrom(
              foregroundColor: tokens.textPrimary,
              side: BorderSide(color: tokens.ringTrack),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

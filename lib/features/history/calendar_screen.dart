import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/date.dart';
import '../../shared/ring/mini_ring.dart';
import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';
import 'day_detail_sheet.dart';

/// Calendar history: a month grid where each day is a mini ring of that day's
/// task split. Tap a day to see its detail. Future days are dimmed and inert.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month; // first day of the focused month

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  bool get _atCurrentMonth {
    final now = DateTime.now();
    return _month.year == now.year && _month.month == now.month;
  }

  void _shiftMonth(int by) {
    setState(() => _month = DateTime(_month.year, _month.month + by));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text('Your progress'),
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              _MonthHeader(
                label: '${DayKey.monthName(_month.month)} ${_month.year}',
                onPrev: () => _shiftMonth(-1),
                // Don't browse past the current month — nothing to show there.
                onNext: _atCurrentMonth ? null : () => _shiftMonth(1),
              ),
              const SizedBox(height: 12),
              const _WeekdayLabels(),
              const SizedBox(height: 8),
              Expanded(child: _grid(tasks, theme)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(List<Task> tasks, ThemeData theme) {
    final tokens = GreyscaleTokens.of(context);
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final leadingBlanks = _month.weekday - 1; // Monday-start grid

    final cells = <Widget>[];
    for (var i = 0; i < leadingBlanks; i++) {
      cells.add(const SizedBox.shrink());
    }
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_month.year, _month.month, day);
      final key = DayKey.of(date);
      final isFuture = date.isAfter(todayDate);
      final isToday = date == todayDate;
      final segments = <double>[
        for (final t in tasks) (t.secondsByDay[key] ?? 0).toDouble(),
      ];

      cells.add(
        Opacity(
          opacity: isFuture ? 0.28 : 1,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isFuture ? null : () => showDayDetailSheet(context, key),
            child: Center(
              child: MiniRing(
                size: 40,
                segments: segments,
                child: Text(
                  '$day',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: isToday ? tokens.textPrimary : tokens.textSecondary,
                    fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GridView.count(
      crossAxisCount: 7,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      children: cells,
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  final String label;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrev,
          tooltip: 'Previous month',
        ),
        Expanded(
          child: Center(
            child: Text(label, style: theme.textTheme.titleLarge),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: onNext,
          tooltip: 'Next month',
        ),
      ],
    );
  }
}

class _WeekdayLabels extends StatelessWidget {
  const _WeekdayLabels();

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final style = Theme.of(context)
        .textTheme
        .labelSmall
        ?.copyWith(color: tokens.textTertiary);
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: [
        for (final l in labels)
          Expanded(child: Center(child: Text(l, style: style))),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/date.dart';
import '../../shared/ring/segmented_dial.dart';
import '../habits/habits_providers.dart';
import '../habits/models/daily_habits.dart';
import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';
import 'day_detail_sheet.dart';

/// Calendar history: a vertically scrolling list of months. The current month
/// is pinned at the top (it's the newest — there are no future months above it)
/// and scrolling down reveals progressively older months, stopping at the
/// earliest month that has any recorded data. Each day is a segmented mini ring
/// of that day's task split + habits; tap a day for its detail. Future days in
/// the current month are dimmed and inert.
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final habits = ref.watch(habitsProvider).value;

    final months = _monthsToShow(tasks, habits);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        iconTheme: const IconThemeData(size: 20),
        // Explicit left-aligned back chevron, visually flush with the grid
        // content edge / month label (x=12). Left pad 10 accounts for the
        // glyph's internal whitespace so the visible arrow sits under the "J".
        leadingWidth: 44, // 22 pad + 20 icon + 2 slack
        leading: IconButton(
          padding: const EdgeInsets.only(left: 22),
          alignment: Alignment.centerLeft,
          constraints: const BoxConstraints(),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: SafeArea(
        top: false,
        // Tighter horizontal inset so the 7-column grid fits the larger circles.
        child: ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 32),
          itemCount: months.length,
          itemBuilder: (context, i) {
            final month = months[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Month label: left-aligned flush with the grid content edge
                  // (x=12 via the ListView inset), Bold 20.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
                    child: Text(
                      '${DayKey.monthName(month.month)} ${month.year}',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  _monthGrid(context, month, tasks, habits, theme),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Months to show, newest first: the current month down to the earliest month
  /// with any recorded data (task time or a habit record). Falls back to just
  /// the current month when there's no data yet.
  List<DateTime> _monthsToShow(List<Task> tasks, HabitsState? habits) {
    final now = DateTime.now();
    final current = DateTime(now.year, now.month);

    String? earliestKey;
    void consider(String key) {
      if (earliestKey == null || key.compareTo(earliestKey!) < 0) {
        earliestKey = key;
      }
    }

    for (final t in tasks) {
      t.secondsByDay.keys.forEach(consider);
    }
    if (habits != null) {
      habits.days.keys.forEach(consider);
    }

    final DateTime earliest;
    if (earliestKey == null) {
      earliest = current;
    } else {
      final d = DayKey.parse(earliestKey!);
      earliest = DateTime(d.year, d.month);
    }

    final months = <DateTime>[];
    var m = current;
    while (!m.isBefore(earliest)) {
      months.add(m);
      m = DateTime(m.year, m.month - 1);
    }
    return months;
  }

  /// One month's grid. Non-scrolling — it lives inside the outer month scroll.
  /// The day-circle rendering is unchanged from the single-month version.
  Widget _monthGrid(
    BuildContext context,
    DateTime month,
    List<Task> tasks,
    HabitsState? habits,
    ThemeData theme,
  ) {
    final tokens = GreyscaleTokens.of(context);
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    // Sequential 7-across grid starting at day 1 (no weekday alignment).
    final cells = <Widget>[];
    for (var day = 1; day <= daysInMonth; day++) {
      final date = DateTime(month.year, month.month, day);
      final key = DayKey.of(date);
      final isFuture = date.isAfter(todayDate);
      final isToday = date == todayDate;
      final segments = <double>[
        for (final t in tasks) (t.secondsByDay[key] ?? 0).toDouble(),
      ];
      // That day's habits as per-habit done/not-done segments, like the dial.
      final habitStates = <bool>[
        for (final tick in habits?.days[key]?.ticks ?? const []) tick.done,
      ];

      cells.add(
        Opacity(
          opacity: isFuture ? 0.28 : 1,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isFuture ? null : () => showDayDetailSheet(context, key),
            child: Center(
              child: SegmentedDial(
                size: 49,
                compact: true,
                stroke: 5, // a touch thinner than the proportional ~6
                taskTodaySeconds: segments,
                habitStates: habitStates,
                center: Text(
                  '$day',
                  style: theme.textTheme.labelMedium?.copyWith(
                    // Matches Home's Last-10-days numbers: bold (w700), size 12.
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isToday ? tokens.textPrimary : tokens.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 7,
      mainAxisSpacing: 8,
      crossAxisSpacing: 4,
      children: cells,
    );
  }
}

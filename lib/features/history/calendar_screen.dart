import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/date.dart';
import '../../shared/photo_tint.dart';
import '../../shared/ring/segmented_dial.dart';
import '../habits/habits_providers.dart';
import '../habits/models/daily_habits.dart';
import '../photos/models/photo.dart';
import '../photos/photos_repository.dart';
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
                  _MonthGrid(month: month, tasks: tasks, habits: habits),
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

}

/// One month's grid. Non-scrolling — it lives inside the outer month scroll.
/// Watches its own month's photos so each cell can show that day's first capture
/// inside the effort ring. Rings render immediately from tasks/habits; the photos
/// fill in when the month query resolves (no layout shift — the fill sits in a
/// fixed-size slot inside the ring).
class _MonthGrid extends ConsumerWidget {
  const _MonthGrid({
    required this.month,
    required this.tasks,
    required this.habits,
  });

  final DateTime month;
  final List<Task> tasks;
  final HabitsState? habits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tokens = GreyscaleTokens.of(context);
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    final monthKey = DayKey.monthPrefix(month);
    final byDay = ref.watch(photosForMonthProvider(monthKey)).value ??
        const <String, List<Photo>>{};

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

      final dayPhotos = byDay[key] ?? const <Photo>[];
      final hero = dayPhotos.isEmpty ? null : dayPhotos.first; // first capture
      final hasPhoto = hero != null;

      Widget dial = SegmentedDial(
        size: 49,
        compact: true,
        stroke: 5, // a touch thinner than the proportional ~6
        taskTodaySeconds: segments,
        habitStates: habitStates,
        fill: hasPhoto ? _PhotoFill(url: hero.photoUrl) : null,
        center: Text(
          '$day',
          style: theme.textTheme.labelMedium?.copyWith(
            // Matches Home's Last-10-days numbers: bold (w700), size 12.
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: hasPhoto
                ? Colors.white
                : (isToday ? tokens.textPrimary : tokens.textSecondary),
            // Kept legible over the tinted photo.
            shadows: hasPhoto
                ? const [Shadow(color: Color(0xCC000000), blurRadius: 3)]
                : null,
          ),
        ),
      );
      if (dayPhotos.length > 1) {
        dial = Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [dial, const Positioned(top: 5, right: 8, child: _MultipleDot())],
        );
      }

      cells.add(
        Opacity(
          opacity: isFuture ? 0.28 : 1,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: isFuture ? null : () => showDayDetailSheet(context, key),
            child: Center(child: dial),
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

// ── Photo-in-ring tint — a FIXED, uniform treatment on every photo cell so the
// calendar reads consistently. Both values are tuned on screen; adjust here.
/// Photo colour saturation: 1 = full colour, 0 = full greyscale. Lower = more
/// muted toward the app's greyscale world.
const double _kPhotoSaturation = 0.32;
/// Dark scrim painted over the photo. Higher alpha = darker/more muted and a
/// stronger backing for the white day number. 0x9E ≈ 62% black.
const Color _kPhotoTint = Color(0x9E000000);

/// A day's hero photo inside the effort ring: the network image, desaturated
/// toward the app's greyscale, under the fixed dark tint that both mutes it and
/// backs the white day number. The tint is identical on every photo day so the
/// calendar reads consistently. A broken/failed URL falls back to nothing (ring
/// only) so it never breaks the cell; nothing shows until the first frame, so
/// there's no flash of a tinted-but-empty disc.
class _PhotoFill extends StatelessWidget {
  const _PhotoFill({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
      frameBuilder: (ctx, child, frame, wasSync) {
        if (frame == null) return const SizedBox.shrink();
        // Desaturate toward greyscale, then paint the fixed dark tint directly
        // over the image via foregroundDecoration — it always covers the image
        // exactly, with no Stack-sizing surprises.
        return Container(
          foregroundDecoration: const BoxDecoration(color: _kPhotoTint),
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(saturationMatrix(_kPhotoSaturation)),
            child: child,
          ),
        );
      },
    );
  }
}

/// The quiet "more than one photo today" marker, top-right of the cell.
class _MultipleDot extends StatelessWidget {
  const _MultipleDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 5,
      height: 5,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [BoxShadow(color: Color(0x99000000), blurRadius: 2)],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/date.dart';
import '../../core/utils/duration_format.dart';
import '../../shared/ring/segmented_dial.dart';
import '../photos/models/photo.dart';
import '../photos/photos_repository.dart';
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
    final photos =
        ref.watch(photosForDayProvider(dayKey)).value ?? const <Photo>[];
    final date = DayKey.parse(dayKey);
    final habits = history.habits;

    return SafeArea(
      top: false,
      // Scrollable so a heavy day (many photo rows + tasks + habits) scrolls
      // internally instead of overflowing. The sheet is isScrollControlled, so
      // the scroll view shrink-wraps short days and scrolls tall ones.
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Text(
                  '${DayKey.weekday(date.weekday)} '
                  '${DayKey.ordinalDay(date.day)} ${DayKey.monthName(date.month)}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // The day's dual ring, static — same data-driven segmented style as
              // the main dial. Collective view (no task selected), so every
              // task slice is filled; the inner ring is per-habit segments.
              Center(
                child: SegmentedDial(
                  taskTodaySeconds: history.segments,
                  habitStates: [
                    for (final tick in habits?.ticks ?? const []) tick.done,
                  ],
                  size: 200,
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DurationFormat.hm(
                          Duration(seconds: history.totalSeconds),
                        ),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'logged',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              if (photos.isNotEmpty) ...[
                _Captured(photos: photos),
                const SizedBox(height: 16),
              ],

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
                            child: Text(
                              t.name,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontSize: 15,
                              ),
                            ),
                          ),
                          Text(
                            DurationFormat.hm(Duration(seconds: t.seconds)),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 15,
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 16),
                ],
                if (habits != null && habits.total > 0) ...[
                  _SectionLabel(
                    'Habits · ${habits.completed} of ${habits.total}',
                  ),
                  const SizedBox(height: 8),
                  for (final tick in habits.ticks)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        tick.name,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontSize: 15,
                          color: tick.done
                              ? tokens.textTertiary
                              : tokens.textPrimary,
                          decoration: tick.done
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: tokens.textTertiary,
                        ),
                      ),
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// Thumbnail tint — near-raw (day-detail is a close look), just a whisper of
// mute for cohesion with the app. Far lighter than the calendar's heavy tint.
const double _kThumbSaturation = 0.85; // ~full colour
const Color _kThumbTint = Color(0x1A000000); // ~10% black whisper

/// The day's photos as rectangular thumbnails, grouped by task. A quiet summary
/// line ("3 from Running · 1 from Guitar") names the groups (ordered by count,
/// biggest first); thumbnails follow in the same group order, and **within a
/// group chronological (earliest first)** — consistent with the calendar hero
/// being the day's first capture. Tapping does nothing yet (the overlay is 4d).
class _Captured extends StatelessWidget {
  const _Captured({required this.photos});

  final List<Photo> photos;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    // Group by task, keeping each group chronological (earliest first).
    final groups = <String, List<Photo>>{};
    final names = <String, String>{};
    for (final p in photos) {
      (groups[p.taskId] ??= []).add(p);
      names[p.taskId] = p.taskName;
    }
    for (final g in groups.values) {
      g.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }
    // Group order: most photos first; ties broken by the earliest capture.
    final taskIds = groups.keys.toList()
      ..sort((a, b) {
        final byCount = groups[b]!.length.compareTo(groups[a]!.length);
        if (byCount != 0) return byCount;
        return groups[a]!.first.timestamp.compareTo(groups[b]!.first.timestamp);
      });

    final summary = [
      for (final id in taskIds) '${groups[id]!.length} from ${names[id]}',
    ].join('  ·  ');
    final ordered = [for (final id in taskIds) ...groups[id]!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel('Captured'),
        const SizedBox(height: 4),
        Text(
          summary,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: tokens.textSecondary,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final p in ordered) _Thumb(photo: p)],
        ),
      ],
    );
  }
}

/// One rounded-rectangle thumbnail. Fixed size so a slow/broken URL never shifts
/// the layout: a muted placeholder while loading, a blank tile on error.
class _Thumb extends StatelessWidget {
  const _Thumb({required this.photo});

  final Photo photo;

  static const double _w = 56;
  static const double _h = 74;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: _w,
        height: _h,
        child: Image.network(
          photo.photoUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => ColoredBox(color: tokens.ringTrack),
          frameBuilder: (ctx, child, frame, _) {
            if (frame == null) return ColoredBox(color: tokens.surface);
            return Container(
              foregroundDecoration: const BoxDecoration(color: _kThumbTint),
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(
                  _saturationMatrix(_kThumbSaturation),
                ),
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Saturation colour matrix. [s] = 1 unchanged, 0 full greyscale. (Small local
/// copy; the calendar has its own — a shared tint helper is a later tidy.)
List<double> _saturationMatrix(double s) {
  const r = 0.2126, g = 0.7152, b = 0.0722;
  final ir = (1 - s) * r, ig = (1 - s) * g, ib = (1 - s) * b;
  return [
    ir + s,
    ig,
    ib,
    0,
    0,
    ir,
    ig + s,
    ib,
    0,
    0,
    ir,
    ig,
    ib + s,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
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
        child: Text(
          text,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: tokens.textTertiary),
        ),
      ),
    );
  }
}

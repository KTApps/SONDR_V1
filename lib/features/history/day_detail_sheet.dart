import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/date.dart';
import '../../core/utils/duration_format.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/cached_photo.dart';
import '../photos/delete_photo.dart';
import '../photos/models/photo.dart';
import '../photos/photos_repository.dart';
import '../profile/profile_metrics.dart';
import 'day_ring.dart';
import 'history_providers.dart';

/// Ceiling on the sheet's height, as a fraction of screen height. The sheet
/// fits its content below this; a long day stops here and scrolls under its
/// header, leaving the top quarter as scrim to tap.
const double _kSheetMaxHeightFraction = 0.75;

/// The sheet's side gutters, and the space under the header and the photos.
const double kDaySheetGutter = 24;

/// One photo in the row: 3:4.
const double kDayPhotoWidth = 200;
const double kDayPhotoHeight = 267;

/// Between photos.
const double kDayPhotoGap = 8;

/// One task or habit line.
const double kDaySheetRowHeight = 30;

/// The ring beside the date.
const double kDaySheetRingSize = 44;

/// Above and below the hairline that parts tasks from habits.
const double kDaySheetHabitsGap = 10;

/// How a task row brings its photo into place.
const Duration kDaySheetScroll = Duration(milliseconds: 300);

/// A photo's tint here — near-raw, a close look — unchanged from the
/// thumbnails this row replaced.
const double _kPhotoSaturation = 0.85;
const Color _kPhotoTint = Color(0x1A000000);

/// Shows a day as a bottom sheet: the date and the day's ring, the photos
/// taken, the time per task and the habits. Read-only, apart from deleting a
/// photo — history is a record of what was true then.
Future<void> showDayDetailSheet(BuildContext context, String dayKey) {
  final tokens = GreyscaleTokens.of(context);
  final media = MediaQuery.of(context);
  return showModalBottomSheet(
    context: context,
    backgroundColor: tokens.surface,
    isScrollControlled: true,
    // Swiping down still dismisses; there is just no bar to say so.
    showDragHandle: false,
    // A ceiling, not a height: the sheet fits its content and a long day
    // stops here, its top well clear of the Dynamic Island with scrim above
    // to tap.
    constraints: BoxConstraints(
      maxHeight: media.size.height * _kSheetMaxHeightFraction,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => DayDetailSheet(dayKey: dayKey),
  );
}

class DayDetailSheet extends ConsumerStatefulWidget {
  const DayDetailSheet({super.key, required this.dayKey});

  final String dayKey;

  @override
  ConsumerState<DayDetailSheet> createState() => _DayDetailSheetState();
}

class _DayDetailSheetState extends ConsumerState<DayDetailSheet> {
  final ScrollController _row = ScrollController();

  /// The photo the rest of the sheet speaks about: the one whose left edge
  /// is nearest the gutter, or the last once the row is scrolled to its end.
  int _current = 0;

  /// A task row is bringing its photo into place; the scroll on the way
  /// there does not change which photo is current.
  bool _steering = false;

  int _count = 0;

  static const double _stride = kDayPhotoWidth + kDayPhotoGap;

  @override
  void initState() {
    super.initState();
    _row.addListener(_onScroll);
  }

  @override
  void dispose() {
    _row.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_steering || _count == 0 || !_row.hasClients) return;
    final position = _row.position;
    final atEnd =
        position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent - 0.5;
    final next = atEnd
        ? _count - 1
        : (position.pixels / _stride).round().clamp(0, _count - 1);
    if (next != _current) setState(() => _current = next);
  }

  Future<void> _showPhoto(int index) async {
    if (!_row.hasClients) return;
    setState(() => _current = index);
    _steering = true;
    try {
      await _row.animateTo(
        math.min(index * _stride, _row.position.maxScrollExtent),
        duration: kDaySheetScroll,
        curve: Curves.easeOut,
      );
    } finally {
      _steering = false;
    }
  }

  Future<void> _delete(Photo photo) async {
    HapticFeedback.lightImpact();
    await confirmDeletePhoto(context, ref, photo);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final history = ref.watch(dayHistoryProvider(widget.dayKey));
    final photos = [
      ...ref.watch(photosForDayProvider(widget.dayKey)).value ??
          const <Photo>[],
    ]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _count = photos.length;
    final date = DayKey.parse(widget.dayKey);
    final habits = history.habits;
    final hasHabits = habits != null && habits.total > 0;

    final current = photos.isEmpty
        ? null
        : photos[_current.clamp(0, photos.length - 1)];
    final selectedIndex = current == null
        ? null
        : history.taskIds.indexOf(current.taskId);

    // Each task's first photo, for its row to scroll to.
    final firstPhotoOf = <String, int>{};
    for (var i = 0; i < photos.length; i++) {
      firstPhotoOf.putIfAbsent(photos[i].taskId, () => i);
    }

    final supporting = theme.textTheme.bodyMedium?.copyWith(fontSize: 13);
    final figures = supporting?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    final summary = [
      '${DurationFormat.hm(Duration(seconds: history.totalSeconds))} logged',
      if (hasHabits) '${habits.completed} of ${habits.total} habits',
    ].join(' · ');

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        kDaySheetGutter,
        kDaySheetGutter,
        kDaySheetGutter,
        0,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${DayKey.weekday(date.weekday)} '
                  '${DayKey.ordinalDay(date.day)} ${DayKey.monthName(date.month)}',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  summary,
                  key: kDaySheetSummaryKey,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          CalendarDayRing(
            key: kDaySheetRingKey,
            size: kDaySheetRingSize,
            day: date.day,
            isToday: DayKey.of(DateTime.now()) == widget.dayKey,
            segments: history.segments,
            habitStates: [
              for (final tick in habits?.ticks ?? const []) tick.done,
            ],
            photos: photos,
            selectedTaskIndex: (selectedIndex ?? -1) < 0 ? null : selectedIndex,
          ),
        ],
      ),
    );

    Widget line({
      required String name,
      required Color nameColour,
      String? trailing,
      Color? trailingColour,
      VoidCallback? onTap,
      Key? key,
    }) {
      return GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kDaySheetRowHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: kDaySheetGutter),
            child: Row(
              children: [
                Expanded(
                  child: Text(name, style: supporting?.copyWith(color: nameColour)),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 16),
                  Text(trailing, style: figures?.copyWith(color: trailingColour)),
                ],
              ],
            ),
          ),
        ),
      );
    }

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (photos.isNotEmpty) ...[
          const SizedBox(height: kDaySheetGutter),
          SizedBox(
            height: kDayPhotoHeight,
            // Every photo built, not lazily: a lazy row only estimates
            // its length, and "scrolled to the end" has to be exact.
            child: SingleChildScrollView(
              key: kDaySheetPhotosKey,
              controller: _row,
              scrollDirection: Axis.horizontal,
              // The Profile milestones row's: free, no snapping.
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: kDaySheetGutter),
              child: Row(
                children: [
                  for (var i = 0; i < photos.length; i++) ...[
                    if (i > 0) const SizedBox(width: kDayPhotoGap),
                    GestureDetector(
                      onLongPress: () => _delete(photos[i]),
                      child: SizedBox(
                        width: kDayPhotoWidth,
                        height: kDayPhotoHeight,
                        // The Profile milestones row's corners, so the
                        // placeholder is rounded too.
                        child: ClipRRect(
                          key: ValueKey('day-photo-$i'),
                          borderRadius: BorderRadius.circular(
                            kProfileStripRadius * figmaScale(context),
                          ),
                          child: SondrPhoto(
                            url: photos[i].photoUrl,
                            saturation: _kPhotoSaturation,
                            tint: _kPhotoTint,
                            placeholder: (_) =>
                                ColoredBox(color: tokens.ringTrack),
                            error: (_) => ColoredBox(color: tokens.ringTrack),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: kDaySheetGutter),
        for (final t in history.taskTimes)
          () {
            final lit = current == null || current.taskId == t.taskId;
            final first = firstPhotoOf[t.taskId];
            return line(
              key: ValueKey('day-task-${t.taskId}-${t.name}'),
              name: t.name,
              trailing: DurationFormat.hm(Duration(seconds: t.seconds)),
              nameColour: lit ? tokens.textPrimary : tokens.textTertiary,
              trailingColour: lit ? tokens.textSecondary : tokens.textTertiary,
              onTap: first == null ? null : () => _showPhoto(first),
            );
          }(),
        if (hasHabits) ...[
          const SizedBox(height: kDaySheetHabitsGap),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: kDaySheetGutter),
            child: SizedBox(height: 1, child: ColoredBox(color: kHairline)),
          ),
          const SizedBox(height: kDaySheetHabitsGap),
          // The name alone: white when it was done that day, grey when not.
          for (final tick in habits.ticks)
            line(
              name: tick.name,
              nameColour: tick.done ? tokens.textPrimary : tokens.textTertiary,
            ),
        ],
        SizedBox(
          height: kDaySheetGutter + MediaQuery.of(context).padding.bottom,
        ),
      ],
    );

    // The header stays; everything under it scrolls once the sheet is at
    // its ceiling. Below the ceiling the column is just its content.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        Flexible(
          child: SingleChildScrollView(key: kDaySheetBodyKey, child: body),
        ),
      ],
    );
  }
}

/// "2h 55m logged · 1 of 1 habits", under the date.
const Key kDaySheetSummaryKey = ValueKey('day-sheet-summary');

/// The day's ring, beside the date.
const Key kDaySheetRingKey = ValueKey('day-sheet-ring');

/// The photo row.
const Key kDaySheetPhotosKey = ValueKey('day-sheet-photos');

/// Everything under the header, which scrolls at the ceiling.
const Key kDaySheetBodyKey = ValueKey('day-sheet-body');

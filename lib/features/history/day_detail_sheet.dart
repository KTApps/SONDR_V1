import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart' hide Task;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/date.dart';
import '../../core/utils/duration_format.dart';
import '../../shared/cached_photo.dart';
import '../../shared/ring/segmented_dial.dart';
import '../feed/posts_repository.dart';
import '../photos/models/photo.dart';
import '../photos/photos_repository.dart';
import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';
import 'history_providers.dart';

/// Ceiling on the sheet's height, as a fraction of screen height. A photo-heavy
/// day tops out here — around three-quarters up the screen, leaving the top
/// ~quarter as visible, tappable scrim (and the native drag handle well clear of
/// the Dynamic Island). Only a ceiling: light/empty days shrink-wrap below it.
/// The one knob to tune by eye.
const double _kSheetMaxHeightFraction = 0.75;

/// Shows a day's detail as a bottom sheet: the date, that day's dual ring
/// (task split + habit completion), the time logged per task, and the habit
/// snapshot. Read-only — history is a record of what was true then.
Future<void> showDayDetailSheet(BuildContext context, String dayKey) {
  final tokens = GreyscaleTokens.of(context);
  final media = MediaQuery.of(context);
  return showModalBottomSheet(
    context: context,
    backgroundColor: tokens.surface,
    isScrollControlled: true,
    showDragHandle: true,
    // Cap the sheet's height so it never reaches the Dynamic Island. Without
    // this, isScrollControlled lets a photo-heavy day grow the sheet to full
    // height, pushing the native drag handle under the notch and leaving no
    // scrim to tap — a dismissal trap. Capped at a fraction of screen height,
    // a heavy day tops out with the upper ~quarter as tappable scrim, the
    // handle stays fully visible, and the body scrolls within the cap; light
    // days shrink-wrap below the ceiling.
    constraints: BoxConstraints(
      maxHeight: media.size.height * _kSheetMaxHeightFraction,
    ),
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
      // internally within the capped height instead of overflowing. The height
      // cap (see showDayDetailSheet) keeps the sheet and its native drag handle
      // clear of the Dynamic Island; this view just scrolls inside that cap and
      // shrink-wraps short days.
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
                      child: Row(
                        children: [
                          _HabitDot(done: tick.done),
                          const SizedBox(width: 10),
                          Text(
                            tick.name,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontSize: 15,
                            ),
                          ),
                        ],
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
    return GestureDetector(
      onTap: () => _showPhotoOverlay(context, photo),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: _w,
          height: _h,
          // Cached (survives reopening the sheet) with the near-raw tint; a
          // muted placeholder while loading, a blank tile on error.
          child: SondrPhoto(
            url: photo.photoUrl,
            saturation: _kThumbSaturation,
            tint: _kThumbTint,
            placeholder: (_) => ColoredBox(color: tokens.surface),
            error: (_) => ColoredBox(color: tokens.ringTrack),
          ),
        ),
      ),
    );
  }
}

/// Tapping a thumbnail opens a lightweight scrim overlay (not a route push) with
/// the full untinted photo and its session detail.
void _showPhotoOverlay(BuildContext context, Photo photo) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, _, _) => _PhotoOverlay(photo: photo),
    transitionBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}

/// The expanded photo: full and untinted (a close look, meant to be enjoyed),
/// with session detail beneath — task, duration, time of day, and a milestone
/// line only when the photo carries [Photo.milestoneHours]. A Share action
/// appears **only** when the photo's task has passed 20h lifetime
/// (milestonesReached >= 1); below that it's absent. Tapping the card is
/// absorbed; tapping the scrim dismisses.
class _PhotoOverlay extends ConsumerStatefulWidget {
  const _PhotoOverlay({required this.photo});

  final Photo photo;

  @override
  ConsumerState<_PhotoOverlay> createState() => _PhotoOverlayState();
}

class _PhotoOverlayState extends ConsumerState<_PhotoOverlay> {
  bool _sharing = false;

  /// Share this session photo to the feed. Private-first: copy the binary into
  /// the friends-readable posts space (download the owner-only original, then
  /// re-upload via [PostsRepository.uploadPostPhoto]) and post the POSTS url —
  /// the private original doc/binary is never touched or referenced.
  Future<void> _share() async {
    final posts = ref.read(postsRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    if (posts == null) {
      _toast(messenger, 'Sign in to share.');
      return;
    }
    setState(() => _sharing = true);
    try {
      final bytes = await FirebaseStorage.instance
          .ref(widget.photo.storagePath)
          .getData(10 * 1024 * 1024);
      if (bytes == null) throw StateError('no photo bytes');
      final dir = Directory.systemTemp.createTempSync('sondr_share');
      final file = File('${dir.path}/share.jpg');
      await file.writeAsBytes(bytes);

      final postsUrl = await posts.uploadPostPhoto(file);
      await posts.createSessionPost(
        taskName: widget.photo.taskName,
        sessionSeconds: widget.photo.sessionSeconds,
        photoUrl: postsUrl,
      );
      if (!mounted) return;
      navigator.pop(); // close the overlay
      _toast(messenger, 'Shared to your feed.');
    } catch (e) {
      debugPrint('SONDR session share error: $e');
      if (mounted) {
        setState(() => _sharing = false);
        _toast(messenger, 'Couldn’t share. Please try again.');
      }
    }
  }

  void _toast(ScaffoldMessengerState messenger, String message) {
    messenger
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];
    final task = tasks.where((t) => t.id == photo.taskId).firstOrNull;
    final canShare = task != null && task.milestonesReached >= 1;

    final duration = DurationFormat.hm(Duration(seconds: photo.sessionSeconds));
    final time = MaterialLocalizations.of(
      context,
    ).formatTimeOfDay(TimeOfDay.fromDateTime(photo.capturedAt));

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: GestureDetector(
          onTap: () {}, // absorb taps so the card itself never dismisses
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.6,
                  ),
                  // The full untinted photo, routed through the shared cache
                  // (so reopening the overlay doesn't re-fetch) while keeping
                  // the Image widget's intrinsic sizing, spinner and broken-
                  // image fallback exactly as before.
                  child: Image(
                    image: cachedPhotoProvider(photo.photoUrl),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Container(
                      width: 220,
                      height: 280,
                      color: tokens.ringTrack,
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: tokens.textTertiary,
                      ),
                    ),
                    loadingBuilder: (ctx, child, progress) => progress == null
                        ? child
                        : Container(
                            width: 220,
                            height: 280,
                            color: tokens.surface,
                            alignment: Alignment.center,
                            child: const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                photo.taskName,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$duration · $time',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              if (photo.milestoneHours != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${photo.milestoneHours} hour milestone',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
              ],
              if (canShare) ...[
                const SizedBox(height: 16),
                if (_sharing)
                  const SizedBox(
                    height: 40,
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: _share,
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('Share'),
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.textPrimary,
                      textStyle: theme.textTheme.labelLarge,
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Habit completion marker: a solid dot (done, primary tone) or a hollow
/// outlined dot (not done, muted tone). Carries the state the strikethrough used
/// to; the label stays plainly legible beside it.
class _HabitDot extends StatelessWidget {
  const _HabitDot({required this.done});

  final bool done;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? tokens.textPrimary : Colors.transparent,
        border: done
            ? null
            : Border.all(color: tokens.textTertiary, width: 1.5),
      ),
    );
  }
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

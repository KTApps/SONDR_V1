import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/date.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/cached_photo.dart';
import '../../shared/ring/ring_dial.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_error.dart';
import '../../shared/sondr_header.dart';
import '../../shared/sondr_loading.dart';
import '../history/day_detail_sheet.dart';
import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';
import 'collages_repository.dart';
import 'models/collage.dart';
import 'models/photo.dart';
import 'photos_repository.dart';
import 'widgets/collage_grid.dart';

/// A completed milestone ring with its figure in the middle.
///
/// One shape for the whole feature: the task rows anchor on a large one, the
/// journey's band headers on a small one. Always a FULL ring at the bright
/// emphasis tone — these are stretches already finished, never progress
/// (that distinction is [ProgressRing]'s, and it is why this passes
/// highlightedSegment rather than letting the palette ramp).
class _DoneRing extends StatelessWidget {
  const _DoneRing({required this.size, required this.label});

  final double size;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    return RingDial(
      size: size * scale,
      taskSegments: const [1.0],
      highlightedSegment: 0,
      habitProgress: 0,
      showInnerRing: false,
      center: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 12 * scale,
          fontWeight: FontWeight.w700,
          color: tokens.textPrimary,
        ),
      ),
    );
  }
}

/// The last day this task had any time logged, as a sortable "yyyy-mm-dd".
/// Empty when it has never been worked, which sorts last.
String _lastActive(Task task) {
  var latest = '';
  task.secondsByDay.forEach((day, seconds) {
    if (seconds > 0 && day.compareTo(latest) > 0) latest = day;
  });
  return latest;
}

/// Which lens the Milestones screen is reading the record through.
enum _Lens { milestones, photos }

/// Milestones: the same record under two lenses.
///
/// The **Milestones** lens is the achievement view — one row per task that has
/// finished a 20h stretch, drilling into that task's journey. The **Photos**
/// lens is the raw one: every photo ever captured, newest first. They are not
/// two features; a photo that no band can place (captured before
/// `cumulativeSeconds` existed) is invisible under the first lens and present
/// under the second, and the gallery is how you know nothing was lost.
class MilestonesScreen extends ConsumerStatefulWidget {
  const MilestonesScreen({super.key});

  @override
  ConsumerState<MilestonesScreen> createState() => _MilestonesScreenState();
}

class _MilestonesScreenState extends ConsumerState<MilestonesScreen> {
  _Lens _lens = _Lens.milestones;

  @override
  Widget build(BuildContext context) {
    final scale = figmaScale(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24 * scale),
              child: const SondrHeader(title: 'Milestones'),
            ),
            SizedBox(height: kSpacingBase * scale),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24 * scale),
              child: Row(
                children: [
                  _LensOption(
                    label: 'Milestones',
                    active: _lens == _Lens.milestones,
                    onTap: () => setState(() => _lens = _Lens.milestones),
                  ),
                  SizedBox(width: kSpacingSection * scale),
                  _LensOption(
                    label: 'Photos',
                    active: _lens == _Lens.photos,
                    onTap: () => setState(() => _lens = _Lens.photos),
                  ),
                ],
              ),
            ),
            SizedBox(height: kSpacingBase * scale),
            Expanded(
              child: switch (_lens) {
                _Lens.milestones => const _MilestonesLens(),
                _Lens.photos => const _PhotosLens(),
              },
            ),
            // Leaving is an exit: supporting grey, last, the same Back the
            // rest of the app uses in place of a chevron. Shared by both
            // lenses — switching lens is not navigation.
            Center(
              child: SondrAction(
                label: 'Back',
                supporting: true,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            SizedBox(height: kSpacingSection * scale),
          ],
        ),
      ),
    );
  }
}

/// One lens name in the toggle.
///
/// The active lens is treated as the heading it is — white and bold, with a
/// hairline under the word; the inactive one takes the app's supporting
/// treatment, grey at regular weight. Tone and weight carry the state, with no
/// pill, no chrome and no sliding indicator (DESIGN.md: white is for the text
/// that must dominate, "the active tab" among them).
///
/// The underline's row is always laid out — transparent when inactive — so
/// changing lens never nudges the content below it.
class _LensOption extends StatelessWidget {
  const _LensOption({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: active ? null : onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: kSpacingPair * scale),
        // Intrinsic width so the rule under the word is exactly the word's
        // width: a stretch inside the unbounded Row would have nothing to
        // measure against.
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15 * scale,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active ? tokens.textPrimary : tokens.textSecondary,
                ),
              ),
              SizedBox(height: kSpacingPair * scale),
              SizedBox(
                height: 1.5 * scale,
                child: ColoredBox(
                  color: active ? tokens.textPrimary : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Milestones lens: one row per task that has finished at least one 20h
/// stretch, most recently worked first. Tapping a row opens that task's
/// journey.
///
/// The lens is the TASK, not the collage. The old screen listed collages —
/// one entry per task+milestone, so a task with three milestones appeared
/// three times and the thing you were actually looking for (how far has
/// Spanish come?) had to be reassembled by eye.
class _MilestonesLens extends ConsumerWidget {
  const _MilestonesLens();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = figmaScale(context);
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    final tasks = [
      for (final t in ref.watch(tasksProvider).value ?? const <Task>[])
        if (t.milestonesReached >= 1) t,
    ]..sort((a, b) => _lastActive(b).compareTo(_lastActive(a)));

    if (tasks.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 24 * scale),
        child: Text(
          'No milestones yet. The first lands at 20 hours.',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13 * scale,
            color: tokens.textSecondary,
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final t in tasks) _TaskRow(task: t),
      ],
    );
  }
}

/// One task: its total as a completed ring, its name, a supporting line, and
/// the most recent photo it has banked. The whole row opens the journey.
class _TaskRow extends ConsumerWidget {
  const _TaskRow({required this.task});

  final Task task;

  static const double _ring = 56;
  static const double _thumb = 44;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    final photos =
        ref.watch(taskBandPhotosProvider(task.id)).value ?? const <Photo>[];
    final supporting = photos.isEmpty
        ? '${task.wholeHours} hours · no photos'
        : '${task.wholeHours} hours · ${photos.length} '
            '${photos.length == 1 ? 'photo' : 'photos'}';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => _TaskJourneyScreen(task: task)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 24 * scale,
          vertical: kSpacingBase * scale,
        ),
        child: Row(
          children: [
            _DoneRing(size: _ring, label: '${task.wholeHours}h'),
            SizedBox(width: kSpacingBase * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    task.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 15 * scale,
                      fontWeight: FontWeight.w700,
                      color: tokens.textPrimary,
                    ),
                  ),
                  SizedBox(height: kSpacingPair * scale),
                  Text(
                    supporting,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13 * scale,
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            // Omitted entirely when the task has banked nothing — an empty
            // frame would promise a photo that is not there.
            if (photos.isNotEmpty) ...[
              SizedBox(width: kSpacingBase * scale),
              ClipRRect(
                borderRadius: BorderRadius.circular(8 * scale),
                child: SizedBox(
                  width: _thumb * scale,
                  height: _thumb * scale,
                  child: SondrPhoto(url: photos.first.photoUrl),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One task's journey: every stretch it has finished, newest at the top, each
/// with the photos taken inside it.
///
/// Highest band first because the question is "where has this got to", and
/// the answer is the most recent stretch — reading downward is reading back
/// in time.
class _TaskJourneyScreen extends ConsumerWidget {
  const _TaskJourneyScreen({required this.task});

  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = figmaScale(context);
    final reached = task.milestonesReached;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24 * scale),
              child: SondrHeader(
                title: '${task.name} · ${task.wholeHours} hours',
              ),
            ),
            SizedBox(height: kSpacingSection * scale),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  for (var b = reached; b >= 1; b--)
                    _BandEntry(
                      task: task,
                      bandHours: b * Task.milestoneStepHours,
                    ),
                ],
              ),
            ),
            Center(
              child: SondrAction(
                label: 'Back',
                supporting: true,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            SizedBox(height: kSpacingSection * scale),
          ],
        ),
      ),
    );
  }
}

/// One finished stretch: its ring, its label, its photos, and the curation
/// that was already here.
///
/// Photos come from the stored [Collage] when there is one — that is the
/// curated or auto-composed set, and editing it is what Edit saves. With no
/// collage doc yet the full band is shown instead, so a stretch is never
/// blank just because nothing has composed it.
class _BandEntry extends ConsumerStatefulWidget {
  const _BandEntry({required this.task, required this.bandHours});

  final Task task;
  final int bandHours;

  @override
  ConsumerState<_BandEntry> createState() => _BandEntryState();
}

class _BandEntryState extends ConsumerState<_BandEntry> {
  bool _editing = false;
  bool _saving = false;
  final Set<String> _removed = {};

  void _toggle(Photo p) => setState(() {
        if (!_removed.remove(p.id)) _removed.add(p.id);
      });

  void _cancel() => setState(() {
        _removed.clear();
        _editing = false;
      });

  Future<void> _save(List<Photo> photos) async {
    final repo = ref.read(collagesRepositoryProvider);
    if (repo == null) return;
    final kept = [for (final p in photos) if (!_removed.contains(p.id)) p.id];
    if (kept.isEmpty) return; // guarded by min-1, belt-and-braces
    setState(() => _saving = true);
    try {
      await repo.saveEdited(widget.task.id, widget.bandHours, kept);
      ref.invalidate(collagesListProvider);
      ref.invalidate(taskBandPhotosProvider(widget.task.id));
      if (mounted) {
        setState(() {
          _removed.clear();
          _editing = false;
          _saving = false;
        });
      }
    } catch (e) {
      debugPrint('SONDR collage edit save error: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    final collage = (ref.watch(collagesListProvider).value ?? const <Collage>[])
        .where((c) =>
            c.taskId == widget.task.id &&
            c.milestoneHours == widget.bandHours)
        .firstOrNull;

    final photos = collage != null
        ? ref.watch(collagePhotosProvider(collage.photoIds.join(','))).value ??
            const <Photo>[]
        : ref
                .watch(bandPhotosProvider('${widget.task.id}|${widget.bandHours}'))
                .value ??
            const <Photo>[];

    final keptCount = photos.length - _removed.length;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        24 * scale,
        0,
        24 * scale,
        kSpacingSection * scale,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _DoneRing(size: 40, label: '${widget.bandHours}h'),
              SizedBox(width: kSpacingBase * scale),
              Expanded(
                child: Text(
                  '${widget.bandHours} hours',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 15 * scale,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              if (photos.isNotEmpty && !_editing)
                SondrAction(
                  label: 'Edit',
                  supporting: true,
                  fontSize: kRowActionSize,
                  onPressed: () => setState(() => _editing = true),
                ),
            ],
          ),
          SizedBox(height: kSpacingBase * scale),
          // A stretch with nothing in it says so in one quiet line. A grid of
          // nothing would read as a loading failure.
          if (photos.isEmpty)
            Text(
              'No photos from this stretch.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13 * scale,
                color: tokens.textSecondary,
              ),
            )
          else
            CollageGrid(
              photos: photos,
              removedIds: _editing ? _removed : null,
              onToggleRemove: _editing ? _toggle : null,
              canMark: _editing ? (_) => keptCount > 1 : null,
            ),
          if (_editing) ...[
            SizedBox(height: kSpacingBase * scale),
            Row(
              children: [
                Text(
                  '$keptCount kept',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13 * scale,
                    color: tokens.textSecondary,
                  ),
                ),
                const Spacer(),
                SondrAction(
                  label: _saving ? 'Saving…' : 'Save',
                  fontSize: kRowActionSize,
                  onPressed: _saving ? null : () => _save(photos),
                ),
                SizedBox(width: SondrActionPair.gap * scale),
                SondrAction(
                  label: 'Cancel',
                  supporting: true,
                  fontSize: kRowActionSize,
                  onPressed: _saving ? null : _cancel,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// Gallery tint — the same whisper of mute the day-detail thumbnails use. A
// gallery is a close look, so the photos stay near-raw.
const double _kGallerySaturation = 0.85;
const Color _kGalleryTint = Color(0x1A000000);

/// The Photos lens: every photo the user has, newest first, under its month.
///
/// It reads the calendar's own month store ([photosForMonthProvider]) rather
/// than a gallery query of its own, so the two surfaces can never disagree
/// about what exists. Months are walked back from today to the month of the
/// first photo; a month that holds nothing renders nothing at all.
class _PhotosLens extends ConsumerWidget {
  const _PhotosLens();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final inset = EdgeInsets.symmetric(horizontal: 24 * scale);

    final earliest = ref.watch(earliestPhotoMonthProvider);
    if (earliest.hasError) {
      return Padding(
        padding: inset,
        child: const SondrError('Could not load your photos.'),
      );
    }
    if (earliest.isLoading) return const SondrLoading();

    final first = earliest.value;
    // Nothing at all is one quiet line. A grid of blank tiles would read as a
    // loading failure, and an explanation of why there are no photos yet is a
    // word the screen does not need.
    if (first == null) {
      return Padding(
        padding: inset,
        child: Text(
          'No photos yet.',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13 * scale,
            color: tokens.textSecondary,
          ),
        ),
      );
    }

    final now = DateTime.now();
    final months = <DateTime>[];
    for (
      var m = DateTime(now.year, now.month);
      !m.isBefore(first);
      m = DateTime(m.year, m.month - 1)
    ) {
      months.add(m);
    }

    return ListView.builder(
      padding: inset,
      itemCount: months.length,
      // Each section watches its own month, so the queries resolve lazily as
      // the gallery is scrolled — the same way the calendar loads months.
      itemBuilder: (_, i) => _MonthSection(month: months[i]),
    );
  }
}

/// One month of the gallery: its name, then its photos newest first.
///
/// Days descend and each day's photos are reversed (the month store keeps them
/// oldest-first for the calendar's hero), so the grid reads strictly backwards
/// in time. There are no per-day headings — the month is the grouping, and a
/// date for every photo would be a wall of labels over a wall of pictures.
class _MonthSection extends ConsumerWidget {
  const _MonthSection({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    final byDay =
        ref.watch(photosForMonthProvider(DayKey.monthPrefix(month))).value ??
        const <String, List<Photo>>{};
    // An empty month is not a month: no label, no gap, nothing. This also
    // covers the frames before its query resolves, so sections appear with
    // their photos rather than as a stack of bare headings.
    if (byDay.isEmpty) return const SizedBox.shrink();

    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    final photos = [for (final d in days) ...byDay[d]!.reversed];

    return Padding(
      padding: EdgeInsets.only(bottom: kSpacingSection * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${DayKey.monthName(month.month)} ${month.year}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 15 * scale,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          SizedBox(height: kSpacingBase * scale),
          _PhotoGrid(photos: photos),
        ],
      ),
    );
  }
}

/// A month's photos as a fixed three-across grid of squares. Tapping one opens
/// that day's detail sheet — the photo's context (what was worked, for how
/// long, what else was captured) is the day, and that sheet already tells it.
///
/// Three columns at every count, unlike [CollageGrid], which adapts its column
/// count to the number of photos: a collage is one composed picture, a gallery
/// is a shelf, and a shelf that changed shape month to month would read as a
/// different thing each time.
class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.photos});

  final List<Photo> photos;

  static const int _columns = 3;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    final gap = kSpacingPair * scale;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      crossAxisCount: _columns,
      mainAxisSpacing: gap,
      crossAxisSpacing: gap,
      children: [
        for (final p in photos)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showDayDetailSheet(context, p.dayKey),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10 * scale),
              child: SondrPhoto(
                url: p.photoUrl,
                saturation: _kGallerySaturation,
                tint: _kGalleryTint,
                placeholder: (_) => ColoredBox(color: tokens.surface),
                error: (_) => ColoredBox(color: tokens.ringTrack),
              ),
            ),
          ),
      ],
    );
  }
}

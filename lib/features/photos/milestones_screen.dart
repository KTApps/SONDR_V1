import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/cached_photo.dart';
import '../../shared/ring/ring_dial.dart';
import '../../shared/sondr_action.dart';
import '../../shared/sondr_header.dart';
import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';
import 'collages_repository.dart';
import 'models/collage.dart';
import 'models/photo.dart';
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

/// Milestones: one row per task that has finished at least one 20h stretch,
/// most recently worked first. Tapping a row opens that task's journey.
///
/// The lens is the TASK, not the collage. The old screen listed collages —
/// one entry per task+milestone, so a task with three milestones appeared
/// three times and the thing you were actually looking for (how far has
/// Spanish come?) had to be reassembled by eye.
class MilestonesScreen extends ConsumerWidget {
  const MilestonesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scale = figmaScale(context);
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    final tasks = [
      for (final t in ref.watch(tasksProvider).value ?? const <Task>[])
        if (t.milestonesReached >= 1) t,
    ]..sort((a, b) => _lastActive(b).compareTo(_lastActive(a)));

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24 * scale),
              child: const SondrHeader(title: 'Milestones'),
            ),
            SizedBox(height: kSpacingSection * scale),
            Expanded(
              child: tasks.isEmpty
                  ? Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24 * scale),
                      child: Text(
                        'No milestones yet. The first lands at 20 hours.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontSize: 13 * scale,
                          color: tokens.textSecondary,
                        ),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (final t in tasks) _TaskRow(task: t),
                      ],
                    ),
            ),
            // Leaving is an exit: supporting grey, last, the same Back the
            // rest of the app uses in place of a chevron.
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

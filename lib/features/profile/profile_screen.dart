import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug_flags.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../shared/cached_photo.dart';
import '../../shared/ring/progress_ring.dart';
import '../auth/account_screen.dart';
import '../debug/debug_panel.dart';
import '../friends/friends_repository.dart';
import '../friends/friends_screen.dart';
import '../habits/habits_providers.dart';
import '../history/calendar_screen.dart';
import '../photos/collages_repository.dart';
import '../photos/collages_screen.dart';
import '../photos/models/collage.dart';
import '../photos/models/photo.dart';
import '../photos/photos_repository.dart';
import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';
import 'profile_providers.dart';

/// The Profile tab. Per the spec the hero is an effort summary — lifetime hours,
/// current streak, milestones hit — followed by tasks-in-progress as mini rings
/// (answering "what is this person working on and how far have they got").
/// Account management is folded in at the bottom. NOT a photo grid.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lifetime = ref.watch(lifetimeDurationProvider);
    final streak = ref.watch(habitStreakProvider);
    final milestones = ref.watch(milestonesReachedProvider);
    final tasks = ref.watch(tasksProvider).value ?? const <Task>[];

    return Scaffold(
      // No AppBar — the redundant "Profile" title is removed (matches Feed).
      // SafeArea drops content below the status bar / island; the scroll view's
      // top inset (8) keeps the summary card off the edge.
      // Non-scrolling page: stats + Friends pinned at top, the In-progress
      // strip scrolls horizontally, and the account section is pinned at the
      // bottom (it scrolls internally only if the tall guest view would
      // otherwise overflow).
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EffortSummary(
                lifetime: lifetime,
                streak: streak,
                milestones: milestones,
              ),
              const SizedBox(height: 12),
              const _FriendsRow(),
              // Gallery doorway — self-spaced (top gap inside), so when it's
              // hidden (no photos) the Friends→Tasks spacing is unchanged.
              const _GalleryDoorway(),
              const _MilestonesDoorway(),
              const SizedBox(height: 28),
              _TasksInProgress(tasks: tasks),
              // QA-only entry — const-false in release builds, so this whole
              // branch (and DebugPanel, referenced only here) tree-shakes out.
              if (kDebugTools) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const DebugPanel()),
                    ),
                    child: const Text('DEBUG PANEL'),
                  ),
                ),
              ],
              Expanded(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SingleChildScrollView(child: const AccountBody()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hero: three figures across one card — total lifetime hours, current day
/// streak, milestones reached. Brightness, not colour, carries the emphasis.
class _EffortSummary extends StatelessWidget {
  const _EffortSummary({
    required this.lifetime,
    required this.streak,
    required this.milestones,
  });

  final Duration lifetime;
  final int streak;
  final int milestones;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final hours = (lifetime.inMinutes / 60).round();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Stat(value: '$hours', label: hours == 1 ? 'hour' : 'hours'),
          ),
          _Divider(tokens: tokens),
          Expanded(
            child: _Stat(value: '$streak', label: 'day streak'),
          ),
          _Divider(tokens: tokens),
          Expanded(
            child: _Stat(
              value: '$milestones',
              label: milestones == 1 ? 'milestone' : 'milestones',
            ),
          ),
        ],
      ),
    );
  }
}

/// Tappable row into the Friends hub, showing the friend count and a badge for
/// any requests awaiting the user.
class _FriendsRow extends ConsumerWidget {
  const _FriendsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final count = ref.watch(friendCountProvider);
    final pending = ref.watch(incomingRequestsProvider).length;

    return Material(
      color: tokens.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(
          context,
        ).push(MaterialPageRoute(builder: (_) => const FriendsScreen())),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Icon(Icons.people_outline, color: tokens.textSecondary),
              const SizedBox(width: 14),
              Text('Friends', style: theme.textTheme.bodyLarge),
              const Spacer(),
              if (pending > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: tokens.ringFillOuter,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$pending new',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tokens.background,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              Text(
                '$count',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
              Icon(Icons.chevron_right, color: tokens.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

// Gallery thumbnails use the near-raw tint (same as day-detail's Captured
// thumbs) — light desaturation + a whisper of dark, via the shared matrix.
const double _kGalleryThumbSaturation = 0.85;
const Color _kGalleryThumbTint = Color(0x1A000000);

/// A doorway into the photo calendar: a strip of the most recent captures, a
/// count, and a chevron — mirrors [_FriendsRow]. Hidden entirely until there's
/// at least one photo. Opens the step-3 [CalendarScreen] (same route pattern as
/// the home "View your progress" CTA).
class _GalleryDoorway extends ConsumerWidget {
  const _GalleryDoorway();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final preview = ref.watch(galleryPreviewProvider).value;
    if (preview == null || preview.total == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CalendarScreen())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                for (final p in preview.recent) ...[
                  _GalleryThumb(photo: p),
                  const SizedBox(width: 6),
                ],
                const Spacer(),
                Text(
                  '${preview.total} captured',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                Icon(Icons.chevron_right, color: tokens.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A doorway into the milestone collages — a preview of the newest collage's
/// photos, a count, and a chevron. Mirrors [_GalleryDoorway]; hidden until there
/// is at least one (non-empty) collage. Opens [CollagesScreen].
class _MilestonesDoorway extends ConsumerWidget {
  const _MilestonesDoorway();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final collages = ref.watch(collagesListProvider).value ?? const <Collage>[];
    if (collages.isEmpty) return const SizedBox.shrink();

    final preview =
        ref
            .watch(collagePhotosProvider(collages.first.photoIds.join(',')))
            .value ??
        const <Photo>[];
    final n = collages.length;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const CollagesScreen())),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                for (final p in preview.take(4)) ...[
                  _GalleryThumb(photo: p),
                  const SizedBox(width: 6),
                ],
                const Spacer(),
                Text(
                  '$n milestone${n == 1 ? '' : 's'}',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: tokens.textSecondary,
                  ),
                ),
                Icon(Icons.chevron_right, color: tokens.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One small gallery thumbnail — fixed size, near-raw tint, graceful fallback.
class _GalleryThumb extends StatelessWidget {
  const _GalleryThumb({required this.photo});

  final Photo photo;

  static const double _size = 34;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: _size,
        height: _size,
        // Cached (survives revisiting the profile) with the near-raw tint; a
        // failed/loading URL shows a muted tile rather than a broken image.
        child: SondrPhoto(
          url: photo.photoUrl,
          saturation: _kGalleryThumbSaturation,
          tint: _kGalleryThumbTint,
          placeholder: (_) => ColoredBox(color: tokens.ringTrack),
          error: (_) => ColoredBox(color: tokens.ringTrack),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.headlineMedium?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: tokens.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider({required this.tokens});
  final GreyscaleTokens tokens;
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 36, color: tokens.ringTrack);
}

/// Tasks-in-progress: one mini ring per task filling toward its current 20-hour
/// milestone band (same semantics as the home dial), the task's lifetime hours
/// in the centre. A wrap so any number of tasks lays out tidily.
class _TasksInProgress extends StatelessWidget {
  const _TasksInProgress({required this.tasks});
  final List<Task> tasks;

  static const double _tileWidth = 84; // matches _TaskTile width
  static const double _colGap = 20;
  static const double _rowGap = 20;
  static const double _oneRowHeight = 120;
  static const double _twoRowHeight = 260;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'In progress',
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        if (tasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Start a task on the timer to see it climb here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: tokens.textSecondary,
              ),
            ),
          )
        else if (tasks.length <= 2)
          // 1–2 tasks: a single horizontal row (no half-empty second row).
          SizedBox(
            height: _oneRowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: tasks.length,
              separatorBuilder: (_, _) => const SizedBox(width: _colGap),
              itemBuilder: (context, i) => _TaskTile(task: tasks[i]),
            ),
          )
        else
          // 3+ tasks: two-row, column-major horizontal strip. Scrolls sideways;
          // with 84px columns + 20 gap inside the 24px page padding, the next
          // column peeks at the right edge.
          SizedBox(
            height: _twoRowHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: (tasks.length / 2).ceil(),
              separatorBuilder: (_, _) => const SizedBox(width: _colGap),
              itemBuilder: (context, c) {
                final topI = c * 2;
                final botI = c * 2 + 1;
                return SizedBox(
                  width: _tileWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TaskTile(task: tasks[topI]),
                      if (botI < tasks.length) ...[
                        const SizedBox(height: _rowGap),
                        _TaskTile(task: tasks[botI]),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final hours = (task.total.inMinutes / 60).round();
    final reached = task.milestonesReached;

    return SizedBox(
      width: 84,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProgressRing(
            size: 72,
            progress: task.milestoneProgress,
            center: Text(
              '${hours}h',
              style: theme.textTheme.labelLarge?.copyWith(
                color: tokens.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            task.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 15,
              color: tokens.textPrimary,
            ),
          ),
          Text(
            reached == 0
                ? 'of ${task.activeMilestoneHours}h'
                : '$reached × 20h',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: tokens.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

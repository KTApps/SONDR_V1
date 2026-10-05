import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug_flags.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/cached_photo.dart';
import '../../shared/ring/progress_ring.dart';
import '../../shared/sondr_action.dart';
import '../auth/account_screen.dart';
import '../auth/guest_prompts.dart';
import '../debug/debug_panel.dart';
import '../friends/friends_repository.dart';
import '../friends/blocked_accounts_screen.dart';
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
    final scale = figmaScale(context);

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
          padding: EdgeInsets.fromLTRB(
            24 * scale,
            16 * scale,
            24 * scale,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EffortSummary(
                lifetime: lifetime,
                streak: streak,
                milestones: milestones,
              ),
              SizedBox(height: kSpacingSection * scale),
              const _FriendsRow(),
              // Gallery doorway — self-spaced (top gap inside), so when it's
              // hidden (no photos) the Friends→Tasks spacing is unchanged.
              const _GalleryDoorway(),
              const _MilestonesDoorway(),
              SizedBox(height: kSpacingBase * scale),
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
              // Quiet entry: blocking is rare, and undoing it has to be possible
          // from somewhere. Only shown once something is blocked.
          if (ref.watch(blockedAccountsProvider).value?.isNotEmpty ?? false)
            Padding(
              padding: EdgeInsets.only(top: kSpacingBase * scale),
              child: Center(
                child: SondrAction(
                  label: 'Blocked accounts',
                  supporting: true,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const BlockedAccountsScreen(),
                    ),
                  ),
                ),
              ),
            ),

          // The footer is pinned to the bottom of the safe area; the
              // flexible space sits here, never closing below a zone break.
              //
              // No scroll view: the page is a fixed Column that fills the safe
              // area. A SingleChildScrollView shorter than its viewport still
              // bounce-drags on iOS, which made the whole page feel loose even
              // though nothing overflowed. Only the in-progress strip scrolls,
              // and only sideways.
              SizedBox(height: kSpacingSection * scale),
              const Spacer(),
              const AccountBody(),
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

    // No container: a filled rounded rectangle signals "tappable", and this
    // block is a read-only summary. It sits bare on the page at the same
    // gutter as everything else (see DESIGN.md).
    return Row(
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
        onTap: () {
          // Friends and handles live on a permanent account.
          if (!requireAccount(
            context,
            ref,
            message:
                'Create an account to pick a handle and add friends. Your '
                'friends and progress stay safe if you change phones.',
          )) {
            return;
          }
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const FriendsScreen()));
        },
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
      padding: EdgeInsets.only(top: kSpacingBase * figmaScale(context)),
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
      padding: EdgeInsets.only(top: kSpacingBase * figmaScale(context)),
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

  /// On the base tier — it was 20, which was neither tier (see DESIGN.md).
  static const double _rowGap = kSpacingBase;

  /// The strip needs a bounded height, so it states exactly what it holds —
  /// no more. These were 120 and 260 against 101-tall tiles, which left ~38 of
  /// dead space at the bottom of the screen.
  static const double _oneRowHeight = _TaskTile.height;
  static const double _twoRowHeight = _TaskTile.height * 2 + _rowGap;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'In progress',
          style: theme.textTheme.titleMedium?.copyWith(
            fontSize: 15 * scale,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: kSpacingBase * scale),
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
            height: _oneRowHeight * scale,
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
            height: _twoRowHeight * scale,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: (tasks.length / 2).ceil(),
              separatorBuilder: (_, _) => SizedBox(width: _colGap * scale),
              itemBuilder: (context, c) {
                final topI = c * 2;
                final botI = c * 2 + 1;
                return SizedBox(
                  width: _tileWidth * scale,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TaskTile(task: tasks[topI]),
                      if (botI < tasks.length) ...[
                        SizedBox(height: _rowGap * scale),
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

  static const double ringSize = 72;
  static const double labelGap = 8;

  /// Unscaled height of one tile: ring + gap + the label's line box. Measured
  /// against the real text metrics rather than guessed — the strip that holds
  /// these needs a bounded height, so it has to be stated somewhere, and
  /// stating it here keeps it next to the parts it is made of.
  static const double height = ringSize + labelGap + 17;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    // The task's real accumulated time — every second ever logged to it, not
    // a band figure and not milestones x 20h. Floored, so it can never claim a
    // milestone the ring has not reached.
    final hours = task.wholeHours;

    // ONE style object, used by both the in-ring figure and the name beneath
    // it, so the two can never drift apart in size or weight.
    final figureStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 12 * scale,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
    );

    return SizedBox(
      width: 84 * scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProgressRing(
            size: ringSize * scale,
            // Progress through the CURRENT 20h block, so the ring keeps
            // climbing toward the next milestone rather than pinning full.
            progress: task.milestoneProgress,
            center: Text('${hours}h', style: figureStyle),
          ),
          SizedBox(height: labelGap * scale),
          Text(
            task.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: figureStyle,
          ),
        ],
      ),
    );
  }
}

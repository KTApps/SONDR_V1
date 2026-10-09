import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug_flags.dart';
import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/cached_photo.dart';
import '../../shared/ring/progress_ring.dart';
import '../../shared/ring/ring_metrics.dart';
import '../auth/account_screen.dart';
import '../auth/guest_prompts.dart';
import '../auth/models/profile.dart';
import '../auth/profile_repository.dart';
import '../debug/debug_panel.dart';
import '../friends/friends_repository.dart';
import '../friends/friends_screen.dart';
import '../habits/habits_providers.dart';
import '../photos/collages_repository.dart';
import '../photos/milestones_screen.dart';
import '../photos/models/collage.dart';
import '../photos/models/photo.dart';
import '../photos/photos_repository.dart';
import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';
import 'profile_providers.dart';

// Photo tints — the near-raw whisper the day-detail thumbnails use, so the
// hero's face and the milestone strip sit in the same family as every other
// photo surface.
const double _kPhotoSaturation = 0.85;
const Color _kPhotoTint = Color(0x1A000000);

/// The Profile tab: who you are, then what you are climbing toward.
///
/// One hero emblem — a grey progress ring with your newest capture at its
/// centre — then the handle, the three figures, and the rest of the page as
/// borderless sections at one rhythm. The account block is the last of those
/// sections rather than something pinned to the bottom of the screen, which is
/// what left a dead void above it when the content above was short.
///
/// NOT a photo grid.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lifetime = ref.watch(lifetimeDurationProvider);
    final streak = ref.watch(habitStreakProvider);
    final milestones = ref.watch(milestonesReachedProvider);
    // Active only: an archived task is not something you are in the middle of.
    final tasks = ref.watch(activeTasksProvider);
    final scale = figmaScale(context);

    return Scaffold(
      // No AppBar — the redundant "Profile" title is removed (matches Feed).
      body: SafeArea(
        child: SingleChildScrollView(
          // Clamping, not bouncing. The page runs past the viewport now, so it
          // genuinely scrolls; on a short page (a new account with no tasks)
          // iOS's bounce made the whole thing feel loose and unanchored, which
          // is why this page refused a scroll view at all before.
          physics: const ClampingScrollPhysics(),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 24 * scale,
              vertical: kSpacingSection * scale,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _HeroEmblem(),
                SizedBox(height: kSpacingSection * scale),
                _EffortSummary(
                  lifetime: lifetime,
                  streak: streak,
                  milestones: milestones,
                ),
                const _Section(child: _FriendsRow()),
                const _Section(child: _MilestonesRow()),
                _Section(child: _TasksInProgress(tasks: tasks)),
                // QA-only entry — const-false in release builds, so this whole
                // branch (and DebugPanel, referenced only here) tree-shakes
                // out. Not a section: no hairline earns it.
                if (kDebugTools) ...[
                  SizedBox(height: kSpacingSection * scale),
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
                const _Section(child: AccountBody()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A section break: one hairline, closer to what came before it than to what
/// comes after.
///
/// Sections are borderless — no cards, no fills, nothing that signals
/// "tappable" around something that isn't — so the only thing between them is
/// a single track-toned line.
///
/// The gaps are deliberately NOT equal. 12 above the line and 24 below it
/// means a heading has more space over it than under it, so it hugs the
/// content it introduces instead of floating between two sections; a break
/// that was 24 either way read as a divider belonging to neither. It also
/// gives the page back 48, which is the difference between one screen and a
/// scroll on most devices. Every break is identical, which is what keeps one
/// rhythm from the hero to the account block.
class _Section extends StatelessWidget {
  const _Section({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(height: kSpacingBase * scale),
        // Unscaled: a hairline is a hairline at every screen size.
        SizedBox(height: 1, child: ColoredBox(color: tokens.ringTrack)),
        SizedBox(height: kSpacingSection * scale),
        child,
      ],
    );
  }
}

/// The hero: a grey progress ring around your newest capture, your handle, and
/// how far the nearest milestone is.
///
/// The ring is a PROGRESS ring and so takes the progress tone
/// ([GreyscaleTokens.ringFillInner], the same grey Home fills with). White is
/// kept for a milestone already finished — the full rings on the Milestones
/// page — so the two can never be confused at a glance.
///
/// The centre is the newest photo across ALL tasks, which means it changes
/// itself as captures happen; before there is one it is your initial. The ring
/// works from the first day either way.
class _HeroEmblem extends ConsumerWidget {
  const _HeroEmblem();

  /// Ø132 outer, a 6 stroke, then an 8 gap, then the photo at Ø104 — four
  /// numbers that only work together: 132 − 2×6 leaves a 120 hole, and a 104
  /// photo centred in it IS the 8 gap. The photo is ≈80% of the outer
  /// diameter, which is what stops the ring reading as a thick frame.
  static const double _ring = 132;
  static const double _stroke = 6;
  static const double _photo = 104;

  /// The first letter of the display name, or failing that the handle.
  /// Empty when there is neither, and then the ring simply stands alone.
  static String initialOf(Profile? profile) {
    for (final source in [profile?.displayName, profile?.username]) {
      final trimmed = (source ?? '').trim();
      if (trimmed.isNotEmpty) return trimmed.substring(0, 1).toUpperCase();
    }
    return '';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    final next = ref.watch(nextMilestoneProvider);
    final profile = ref.watch(currentProfileProvider).value;
    // photosRecent orders by timestamp descending, so the head of this list is
    // the newest capture across every task.
    final recent =
        ref.watch(galleryPreviewProvider).value?.recent ?? const <Photo>[];
    final newest = recent.isEmpty ? null : recent.first;

    final handle = profile?.username ?? '';
    final subline = next == null
        ? 'No task in progress.'
        : '${next.hoursRemaining}h to your next milestone';

    return Column(
      children: [
        ProgressRing(
          size: _ring * scale,
          stroke: _stroke * scale,
          // An empty grey track when there is nothing to climb, and never a
          // closed one: see [shownProgress].
          progress: shownProgress(next?.progress ?? 0),
          center: SizedBox(
            width: _photo * scale,
            height: _photo * scale,
            child: newest == null
                ? Center(
                    child: Text(
                      initialOf(profile),
                      style: theme.textTheme.displayLarge?.copyWith(
                        fontSize: 44 * scale,
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                    ),
                  )
                : ClipOval(
                    child: SondrPhoto(
                      url: newest.photoUrl,
                      saturation: _kPhotoSaturation,
                      tint: _kPhotoTint,
                      placeholder: (_) => ColoredBox(color: tokens.surface),
                      error: (_) => ColoredBox(color: tokens.surface),
                    ),
                  ),
          ),
        ),
        SizedBox(height: kSpacingBase * scale),
        // The person, at the top of their own page at last. Omitted rather
        // than faked when there is no handle yet — the account block below
        // still offers to set one.
        if (handle.isNotEmpty) ...[
          Text(
            '@$handle',
            style: theme.textTheme.titleLarge?.copyWith(
              fontSize: 20 * scale,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          SizedBox(height: kSpacingPair * scale),
        ],
        Text(
          subline,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13 * scale,
            color: tokens.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Three figures across the page — lifetime hours, current streak, milestones
/// reached. Brightness, not colour, carries the emphasis.
///
/// No box and nothing drawn between them: equal thirds of the page's width is
/// air enough to read as three figures rather than one, which is the job a
/// rule would otherwise do (DESIGN.md).
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
    final hours = (lifetime.inMinutes / 60).round();

    return Row(
      children: [
        Expanded(
          child: _Stat(value: '$hours', label: hours == 1 ? 'hour' : 'hours'),
        ),
        Expanded(child: _Stat(value: '$streak', label: 'day streak')),
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

/// The way into the Friends hub: the word, and what is waiting there.
///
/// A borderless row, not a filled card. A rounded fill reads as a button, and
/// a chevron is a second vocabulary for something a row already says by being
/// tappable (DESIGN.md).
class _FriendsRow extends ConsumerWidget {
  const _FriendsRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final count = ref.watch(friendCountProvider);
    final pending = ref.watch(incomingRequestsProvider).length;

    final metadata = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 12 * scale,
      fontWeight: FontWeight.w700,
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
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
      child: Row(
        children: [
          Text(
            'Friends',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 15 * scale,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          const Spacer(),
          // A waiting request is the one thing here worth being told, so it
          // is at full tone — as text, not as a filled pill.
          if (pending > 0) ...[
            Text(
              '$pending new',
              style: metadata?.copyWith(color: tokens.textPrimary),
            ),
            SizedBox(width: kSpacingBase * scale),
          ],
          // A count of zero tells the reader nothing and costs a number.
          if (count > 0)
            Text('$count', style: metadata?.copyWith(color: tokens.textTertiary)),
        ],
      ),
    );
  }
}

/// The way into the Milestones page: the word, the count, and a strip of the
/// most recent milestone's photos beneath it.
///
/// Borderless like Friends, and it opens the page on its default lens — the
/// row is always here, so the Photos lens is one tab away once you arrive.
class _MilestonesRow extends ConsumerWidget {
  const _MilestonesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    final collages = ref.watch(collagesListProvider).value ?? const <Collage>[];
    final n = collages.length;
    final List<Photo> strip;
    if (n > 0) {
      final ids = collages.first.photoIds.join(',');
      strip = ref.watch(collagePhotosProvider(ids)).value ?? const <Photo>[];
    } else {
      strip = const <Photo>[];
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MilestonesScreen())),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Milestones',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 15 * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              const Spacer(),
              if (n > 0)
                Text(
                  '$n',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w700,
                    color: tokens.textTertiary,
                  ),
                ),
            ],
          ),
          if (strip.isNotEmpty) ...[
            SizedBox(height: kSpacingBase * scale),
            Row(
              children: [
                for (final p in strip.take(4)) ...[
                  _GalleryThumb(photo: p),
                  SizedBox(width: kSpacingPair * scale),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Tasks-in-progress: one grey ring per active task, filling toward its next
/// 20-hour mark with that mark's figure in the middle.
///
/// ONE row, scrolling sideways — a few rings visible and the rest a swipe
/// away. Listing every task down the page instead is what turned this section
/// into the bulk of a long scroll; the section's job is "what am I on", which
/// a row answers and a grid buries.
class _TasksInProgress extends StatelessWidget {
  const _TasksInProgress({required this.tasks});

  final List<Task> tasks;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'In progress',
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 15 * scale,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            // The same set the row scrolls through: tasks not archived.
            if (tasks.isNotEmpty)
              Text(
                '${tasks.length} active',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textTertiary,
                ),
              ),
          ],
        ),
        SizedBox(height: kSpacingBase * scale),
        if (tasks.isEmpty)
          Text(
            'Start a task on the timer to see it climb here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13 * scale,
              color: tokens.textSecondary,
            ),
          )
        else
          // One tile tall whatever the task count — the row grows sideways,
          // never downward. A scroll view around a Row rather than a ListView
          // on purpose: a ListView needs its cross-axis extent declared, and
          // the declared number was a hair under what a 12pt line actually
          // measures, which clipped the task names by a fraction of a pixel.
          // This takes its height from the tiles themselves.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Row(
              children: [
                for (var i = 0; i < tasks.length; i++) ...[
                  if (i > 0) SizedBox(width: kSpacingSection * scale),
                  _TaskTile(task: tasks[i]),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});
  final Task task;

  static const double ringSize = 56;
  static const double labelGap = 8;
  static const double width = 84;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    // ONE style object, used by both the in-ring figure and the name beneath
    // it, so the two can never drift apart in size or weight.
    final figureStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 12 * scale,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
    );

    return SizedBox(
      width: width * scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ProgressRing(
            size: ringSize * scale,
            stroke: thinRingStroke(ringSize * scale),
            // Progress through the CURRENT 20h block, so the ring keeps
            // climbing toward the next milestone rather than pinning full —
            // and clamped, so a first session shows and a last hour doesn't
            // read as finished.
            progress: shownProgress(task.milestoneProgress),
            // The TARGET, not the total: the figure names the thing the ring
            // is filling toward, which is what the ring is about. Lifetime
            // hours are up in the figures at the top of the page.
            center: Text('${task.activeMilestoneHours}h', style: figureStyle),
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

/// One small photo in the milestones strip — fixed size, near-raw tint, and a
/// muted tile rather than a broken image when a URL fails.
class _GalleryThumb extends StatelessWidget {
  const _GalleryThumb({required this.photo});

  final Photo photo;

  static const double _size = 34;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8 * scale),
      child: SizedBox(
        width: _size * scale,
        height: _size * scale,
        child: SondrPhoto(
          url: photo.photoUrl,
          saturation: _kPhotoSaturation,
          tint: _kPhotoTint,
          placeholder: (_) => ColoredBox(color: tokens.ringTrack),
          error: (_) => ColoredBox(color: tokens.ringTrack),
        ),
      ),
    );
  }
}

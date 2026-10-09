import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/cached_photo.dart';
import '../../shared/ring/progress_ring.dart';
import '../../shared/home_metrics.dart';
import '../../shared/ring/ring_metrics.dart';
import '../auth/account_screen.dart';
import '../auth/guest_prompts.dart';
import '../auth/models/profile.dart';
import '../auth/handle_screen.dart';
import '../auth/profile_repository.dart';
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

/// The Profile tab, laid on Home's skeleton.
///
/// The title, the hero band, the supporting line and the first full-width
/// block sit on Home's exact vertical lines (see
/// [lib/shared/home_metrics.dart]) — the handle where the task selector is,
/// the emblem in the dial's band at the dial's diameter, the next-milestone
/// line where the collective hint is, the totals where "Last 10 days" starts.
/// Moving between the two tabs should read as one page changing its contents
/// rather than two pages that happen to be adjacent.
///
/// It scrolls, and only just: the content down to the in-progress row fills
/// the first screen and the account block sits below the fold, a short pull
/// away. NOT a photo grid.
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
    final gap = SizedBox(height: kSpacingBase * scale);

    return Scaffold(
      // No AppBar and no SafeArea — Home has neither, and the whole point is
      // that a y on this page is the same y on that one.
      body: SingleChildScrollView(
        // Clamping, not bouncing: the page runs just past the viewport, and a
        // bounce on a page this close to fitting reads as slack.
        physics: const ClampingScrollPhysics(),
        child: Stack(
          children: [
            // The flowing half, and the Stack's sizing child: it starts on
            // Home's block line, so everything above can be pinned over the
            // space its top padding leaves.
            Padding(
              padding: EdgeInsets.only(
                top: kHomeBlockTop * scale,
                left: kHomeGutter * scale,
                right: kHomeGutter * scale,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Totals(
                    lifetime: lifetime,
                    streak: streak,
                    milestones: milestones,
                  ),
                  gap,
                  const _MilestonesRow(),
                  gap,
                  const _FriendsRow(),
                  gap,
                  _TasksInProgress(tasks: tasks),
                  // Below the fold from here: the account block is something
                  // you go looking for, not something the page leads with.
                  SizedBox(height: kSpacingSection * scale),
                  const AccountBody(),
                ],
              ),
            ),
            // Home's title line.
            Positioned(
              top: kHomeTitleTop * scale,
              left: 0,
              right: 0,
              child: const Center(child: _HandleTitle()),
            ),
            // Home's dial band, at the dial's diameter.
            Positioned(
              top: kHomeDialTop * scale,
              left: 0,
              right: 0,
              child: const Center(child: _HeroEmblem()),
            ),
            // Home's supporting line.
            Positioned(
              top: kHomeSupportingTop * scale,
              left: 0,
              right: 0,
              child: const Center(child: _NextMilestoneLine()),
            ),
          ],
        ),
      ),
    );
  }
}

/// The page's title: the person whose page it is.
///
/// Exactly Home's selector type and padding (20/bold, 8/4), so the two titles
/// share a baseline rather than merely a top. With no handle set it offers to
/// set one — the same fallback the account block used to carry alone.
class _HandleTitle extends ConsumerWidget {
  const _HandleTitle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final handle = ref.watch(currentProfileProvider).value?.username ?? '';

    final style = theme.textTheme.titleLarge?.copyWith(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
    );
    const padding = EdgeInsets.symmetric(
      horizontal: kHomeTitlePadH,
      vertical: kHomeTitlePadV,
    );

    if (handle.isEmpty) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const HandleScreen()),
        ),
        child: Padding(
          padding: padding,
          child: Text('Set your handle', style: style),
        ),
      );
    }
    return Padding(
      padding: padding,
      child: Text('@$handle', style: style),
    );
  }
}

/// The hero: a grey progress ring around your newest capture.
///
/// Sized to Home's dial so the rows beneath line up across the tabs, with its
/// own proportions carried across rather than re-picked — the stroke and the
/// photo keep the same share of the diameter they had at 132, which is what
/// stops a bigger ring reading as a heavier one.
///
/// The ring is a PROGRESS ring and takes the progress tone
/// ([GreyscaleTokens.ringFillInner]). White is kept for a milestone already
/// finished, so the two can never be confused at a glance.
///
/// The centre is the newest photo across ALL tasks, so it changes itself as
/// captures happen; before there is one it is your initial. The ring works
/// from the first day either way.
class _HeroEmblem extends ConsumerWidget {
  const _HeroEmblem();

  /// The emblem's own proportions, as shares of its diameter: a 6 stroke and a
  /// 104 photo on the 132 ring they were measured at.
  static const double _strokeShare = 6 / 132;
  static const double _photoShare = 104 / 132;

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

    final size = kHomeDialSize * scale;
    final photo = size * _photoShare;

    return ProgressRing(
      size: size,
      stroke: size * _strokeShare,
      // An empty grey track when there is nothing to climb, and never a
      // closed one: see [shownProgress].
      progress: shownProgress(next?.progress ?? 0),
      center: SizedBox(
        width: photo,
        height: photo,
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
    );
  }
}

/// How far the nearest milestone is.
///
/// The same band, type and tone as Home's collective hint, so the line lands
/// on the same baseline there and here rather than merely in the same region.
class _NextMilestoneLine extends ConsumerWidget {
  const _NextMilestoneLine();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final next = ref.watch(nextMilestoneProvider);
    final text = next == null
        ? 'No task in progress.'
        : '${next.hoursRemaining}h to your next milestone';

    return SizedBox(
      height: kHomeSupportingHeight,
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: tokens.textTertiary),
        ),
      ),
    );
  }
}

/// Three figures across the page — lifetime hours, current streak, milestones
/// reached — sitting where Home's "Last 10 days" heading sits, at that
/// heading's size. Brightness, not colour, carries the emphasis.
///
/// No box and nothing drawn between them: equal thirds of the page's width is
/// air enough to read as three figures rather than one, which is the job a
/// rule would otherwise do (DESIGN.md).
class _Totals extends StatelessWidget {
  const _Totals({
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
      // Tops, not centres: a label that wraps to two lines would otherwise
      // push its own figure down and drag the other two up with it, and the
      // figures are the thing that has to sit on Home's line.
      crossAxisAlignment: CrossAxisAlignment.start,
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
    final scale = figmaScale(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Home's "Last 10 days" heading size, so the two blocks read as the
        // same rung of the page rather than one shouting over the other.
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 20 * scale,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
        SizedBox(height: kSpacingPair * scale),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 12 * scale,
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

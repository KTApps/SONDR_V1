import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// The Milestones strip: four equal squares across the content width.
///
/// Four slots whatever the collage holds, so the row keeps one height and one
/// rhythm — a newest collage of two photos fills the first two slots and
/// leaves the rest as space rather than stretching two photos across the whole
/// page. Each slot is a flex share, so the squares size themselves to the
/// gutter instead of to a number: ≈79 on a 393 screen.
/// The page's composition, calibrated on an iPhone 13 Pro (390x844, a 47 top
/// inset and the tab bar at 770, leaving 723 of content).
///
/// EVERY gap here is fixed, and the column is top-anchored. There is no
/// Spacer, no Expanded and no flexible break anywhere in it — flex is what
/// pooled the slack into a void, whether it was spread evenly (45pt chasms
/// between sections) or left to collect at the foot (a 160pt cavern). One row
/// of four photos leaves slack on this device, and the slack belongs in
/// [_kTopMargin]: above the emblem it reads as margin, which is what empty
/// space at the top of a page is for.
///
/// There is LESS of it than the mock estimated. Flutter's text boxes run
/// about 34 taller in total than the nominal sizes — `titleLarge` carries no
/// height factor, so a 20 heading measures nearer 24 — and the margin is what
/// pays for that, since absorbing is its whole job. Every other gap below is
/// the mock's number untouched.
///
/// These are the mock's numbers, not the 6/12/24 ladder's. They are named so
/// the next page does not inherit them by accident.
const double _kTopMargin = 52;
const double _kEmblemSize = 128;
const double _kEmblemToHandle = 9;
const double _kHandleToSubline = 3;
const double _kSublineToStats = 16;
const double _kStatGap = 5;
const double _kBreak = 22;
const double _kUnderHairline = 11;
const double _kHeadingToPhotos = 26;
const double _kHeadingToRings = 20;
const double _kTabClearance = 28;

/// Section headings take the app's Heading token — the same 20/bold Home puts
/// on "Last 10 days".
const double _kHeadingSize = 20;

/// The counts beside them.
const double _kCountSize = 14;

/// The stats' figures and their labels.
const double _kStatFigureSize = 22;
const double _kStatLabelSize = 12;

/// The hairline. Darker than [GreyscaleTokens.ringTrack], which is a RING
/// tone: a rule between sections should part them without being read as one
/// more thing on the page.
const Color _kHairline = Color(0xFF242424);

const int _kStripSlots = 4;

/// The in-progress rings: four slots and the gap between them.
const int _kRingSlots = 4;
const double _kRingGap = 14;
const double _kStripGap = 8;
const double _kStripRadius = 13;

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
        // The viewport, measured. Everything about where the fold falls comes
        // from this number rather than from a guess about the device.
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            // Clamping, not bouncing. The page genuinely runs past the
            // viewport now; on iOS a bounce at the top of a page this
            // deliberately composed reads as slack.
            physics: const ClampingScrollPhysics(),
            child: Padding(
              // The page's own edge: 12 top and bottom, not 24. The section
              // breaks below carry the page's rhythm, and the first and last
              // of them were being doubled up on by a full section gap
              // against the screen edge. The 24 gutter either side is
              // untouched.
              padding: EdgeInsets.symmetric(horizontal: 24 * scale),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // THE FIRST SCREEN. Floored to the viewport's own height
                  // so whatever follows begins past the bottom edge of
                  // whatever device this is — a fixed spacer would have been
                  // right on one phone and wrong on every other.
                  //
                  // Top-anchored, and every gap inside it a fixed SizedBox.
                  // There is no Spacer, no Expanded and no flexible break
                  // here: flex is what pooled the slack into a void, spread
                  // evenly as chasms between the sections or left to collect
                  // at the foot as a cavern. The slack lives in the top
                  // margin above the emblem instead, where empty space at the
                  // top of a page reads as margin.
                  ConstrainedBox(
                    constraints: BoxConstraints(minHeight: viewport.maxHeight),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: _kTopMargin * scale),
                        const _HeroEmblem(),
                        SizedBox(height: _kSublineToStats * scale),
                        _EffortSummary(
                          lifetime: lifetime,
                          streak: streak,
                          milestones: milestones,
                        ),
                        SizedBox(height: _kBreak * scale),
                        const _Hairline(),
                        SizedBox(height: _kUnderHairline * scale),
                        const _FriendsRow(),
                        SizedBox(height: _kBreak * scale),
                        const _Hairline(),
                        SizedBox(height: _kUnderHairline * scale),
                        const _MilestonesRow(),
                        SizedBox(height: _kBreak * scale),
                        const _Hairline(),
                        SizedBox(height: _kUnderHairline * scale),
                        _TasksInProgress(tasks: tasks),
                        SizedBox(height: _kTabClearance * scale),
                      ],
                    ),
                  ),
                  // BELOW THE FOLD. Signed in, the email, Sign out and the
                  // QA word — things you go looking for, never the first
                  // thing the page offers.
                  const _Section(child: AccountBody()),
                  SizedBox(height: kSpacingBase * scale),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The line itself. Unscaled: a hairline is a hairline at every screen size.
class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 1, child: ColoredBox(color: _kHairline));
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

  /// Ø128, with the stroke and the photo at the shares they were measured at
  /// on the 132 ring: a 6 stroke and a 104 photo become ≈5.8 and ≈100.8 here.
  /// The photo stays ≈80% of the outer diameter, which is what stops the ring
  /// reading as a thick frame.
  static const double _ring = _kEmblemSize;
  static const double _stroke = _ring * 6 / 132;
  static const double _photo = _ring * 104 / 132;

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
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 13 * scale,
      color: tokens.textSecondary,
    );

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
        SizedBox(height: _kEmblemToHandle * scale),
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
          SizedBox(height: _kHandleToSubline * scale),
        ],
        // The FIGURE is what you read; the sentence around it is the frame.
        // One Text, so the two sit on one baseline.
        Text.rich(
          TextSpan(
            children: next == null
                ? [TextSpan(text: 'No task in progress.', style: quiet)]
                : [
                    TextSpan(
                      text: '${next.hoursRemaining}h',
                      style: quiet?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                      ),
                    ),
                    TextSpan(text: ' to your next milestone', style: quiet),
                  ],
          ),
          textAlign: TextAlign.center,
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
    final scale = figmaScale(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: _kStatFigureSize * scale,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
        SizedBox(height: _kStatGap * scale),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: _kStatLabelSize * scale,
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
      fontSize: _kCountSize * scale,
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
              fontSize: _kHeadingSize * scale,
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
///
/// The COUNT is [milestonesReachedProvider], the same figure the totals above
/// show. It used to be the number of saved collages, which is a different
/// thing: a collage is written when a milestone is crossed with photos in its
/// band, so a milestone reached with nothing captured, or crossed before the
/// auto-compose existed, had no collage and went uncounted. The photo strip
/// still comes from the newest collage — that is a preview, and a preview may
/// well have less behind it than the count.
class _MilestonesRow extends ConsumerWidget {
  const _MilestonesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    final n = ref.watch(milestonesReachedProvider);
    final collages = ref.watch(collagesListProvider).value ?? const <Collage>[];
    final List<Photo> strip;
    if (collages.isNotEmpty) {
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
                  fontSize: _kHeadingSize * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              const Spacer(),
              if (n > 0)
                Text(
                  '$n',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: _kCountSize * scale,
                    fontWeight: FontWeight.w700,
                    color: tokens.textTertiary,
                  ),
                ),
            ],
          ),
          if (strip.isNotEmpty) ...[
            SizedBox(height: _kHeadingToPhotos * scale),
            Row(
              children: [
                for (var i = 0; i < _kStripSlots; i++) ...[
                  if (i > 0) SizedBox(width: _kStripGap * scale),
                  Expanded(
                    // An empty slot is space, not a frame: a bordered blank
                    // would promise a photo that is not there.
                    child: i < strip.length
                        ? _GalleryThumb(photo: strip[i])
                        : const SizedBox.shrink(),
                  ),
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
                fontSize: _kHeadingSize * scale,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            // A bare number, like the counts on the Friends and Milestones
            // rows above it. The same set the row scrolls through: tasks not
            // archived.
            if (tasks.isNotEmpty)
              Text(
                '${tasks.length}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: _kCountSize * scale,
                  fontWeight: FontWeight.w700,
                  color: tokens.textTertiary,
                ),
              ),
          ],
        ),
        SizedBox(height: _kHeadingToRings * scale),
        if (tasks.isEmpty)
          Text(
            'Start a task on the timer to see it climb here.',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 13 * scale,
              color: tokens.textSecondary,
            ),
          )
        else
          // Four slots across the width, like the photo strip above — the
          // first four tasks, and space where a fifth would be. No scroll:
          // the section answers "what am I on", and four is an answer. The
          // count beside the heading says how many there are in total.
          Row(
            children: [
              for (var i = 0; i < _kRingSlots; i++) ...[
                if (i > 0) SizedBox(width: _kRingGap * scale),
                Expanded(
                  child: i < tasks.length
                      ? _TaskTile(task: tasks[i])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
      ],
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});
  final Task task;

  static const double ringSize = 54;
  static const double labelGap = 8;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    // The figure inside the ring is the bright one; the name under it is
    // supporting — the same relationship every other figure-and-label pair on
    // this page has.
    final figureStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 12 * scale,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
    );
    final nameStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 11 * scale,
      fontWeight: FontWeight.w600,
      color: tokens.textSecondary,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Center(
          child: ProgressRing(
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
        ),
        SizedBox(height: labelGap * scale),
        Text(
          task.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: nameStyle,
        ),
      ],
    );
  }
}

/// One photo in the milestones strip — square, sized by its slot, with the
/// near-raw tint and a muted tile rather than a broken image when a URL fails.
class _GalleryThumb extends StatelessWidget {
  const _GalleryThumb({required this.photo});

  final Photo photo;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    return AspectRatio(
      // Square, so the row's height follows the width the gutter leaves it.
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kStripRadius * scale),
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

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/theme/spacing.dart';
import '../../core/utils/figma_scale.dart';
import '../debug/position_readout.dart';
import '../timer/home_metrics.dart';
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
import '../photos/milestones_screen.dart';
import '../photos/models/photo.dart';
import '../photos/photos_repository.dart';
import '../photos/photo_viewer_sets.dart';
import '../photos/photo_viewer.dart';
import '../tasks/models/task.dart';
import '../tasks/tasks_providers.dart';
import 'milestone_strip.dart';
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
///
/// The margin gave up another 9 when the gap above each heading went to 14,
/// and 46 is the floor the composition allows — a point less and the emblem
/// rides up into the status bar.
/// The page's horizontal content margin. Everything sits inside it EXCEPT the
/// two horizontal scrollers, which span the full screen and carry it as their
/// own leading and trailing scroll padding — so a strip starts on the margin
/// but can be dragged clear of it, and its last item can come to rest there
/// too. A scroller that stopped at the content box looked like a list with
/// nothing after it.
const double _kGutter = 24;

const double _kTopMargin = 46;
const double _kEmblemSize = 128;
/// Symmetric around the handle: the same 9 above it and below it, so the name
/// sits in its own space rather than closer to the ring than to the line it
/// introduces. The pair totals the 18 it did before, so nothing beneath the
/// subtitle moves — only the handle, back onto the line the emblem's own gap
/// originally put it on.
/// The FLOOR on each of the two flexible gaps, not their value.
///
/// They are equal and flexible — ABOVE the handle and BELOW the subtitle,
/// which is to say either side of the pair, never between them. The first
/// screen's height is pinned so the ring labels land on Home's "View your
/// progress" line, and these two are the only gaps that give, splitting
/// whatever the pin leaves over. 16 is the tightest either may become, which
/// is the tier the gap under the pair was declared at before it could flex,
/// so that gap never reads tighter than it used to.
///
/// Flex is here, which the rest of this page still forbids, and the
/// difference is the pin: an Expanded with nothing below it to stop against
/// is what pooled the slack into a void last time. Here the bottom is fixed
/// by a target, so there is a bounded amount to share and exactly two places
/// for it to go.
const double _kHeroGapMin = 16;

/// The CEILING on each flexible gap.
///
/// 32 is the void threshold the composition has always been checked against;
/// past it a gap stops reading as spacing and starts reading as a page that
/// has run out of things to say. The gaps hit it on a sparse page — a guest
/// with no tasks and no milestones has a third less content for the same
/// pinned height — and on the device they reached 117, which put the ring
/// and the line under it at opposite ends of the screen.
///
/// The slack past the ceiling goes to the BOTTOM of the first screen, below
/// the last section, where empty space above the tab bar reads as the end of
/// the page rather than as a hole in the middle of it.
const double _kHeroGapMax = 32;

/// The hero gaps when there is no pin to satisfy — see [_kHeroGapMax] and
/// [_firstScreenHeight]. Between the floor and the ceiling, and fixed,
/// because without a ring row at the bottom there is nothing to line up
/// with and no reason for the hero to stretch at all.
const double _kHeroGapFixed = 18;

/// Handle to subtitle: a PAIR gap, and the tightest number on the page.
///
/// Below [kSpacingPair] deliberately. The two lines are one unit — a name and
/// what the name is doing — and anything looser let the subtitle drift into
/// being its own announcement.
const double _kHandleToSubline = 4;
const double _kStatGap = 5;
const double _kBreak = 22;
/// The gap ABOVE a heading, between the line and the words. Smaller than
/// every gap BELOW a heading (20 at the tightest), so a heading stays bound
/// to the content it introduces rather than to the rule above it.
const double _kUnderHairline = 14;
const double _kHeadingToPhotos = 26;
const double _kHeadingToRings = 20;
/// What is left for the clearance once the rest is paid for. The emblem is
/// fixed and the top margin is spent, so this is the only gap that can give.
const double _kTabClearance = 16;

/// Section headings take the app's Heading token — the same 20/bold Home puts
/// on "Last 10 days".
const double _kHeadingSize = 20;

/// The ring labels' own size — the line the page's bottom is pinned by.
const double _kRingLabelSize = 11;

/// The counts beside them.
const double _kCountSize = 14;

/// The stats' figures and their labels.
const double _kStatFigureSize = 22;
const double _kStatLabelSize = 12;

/// The hairline. Darker than [GreyscaleTokens.ringTrack], which is a RING
/// tone: a rule between sections should part them without being read as one
/// more thing on the page.
const Color _kHairline = Color(0xFF242424);

/// The in-progress rings: the tile's width and the gap between tiles. About
/// four fit the content width and the fifth peeks, which is the only thing
/// telling you the row scrolls.
const double _kRingTileWidth = 72;
const double _kRingGap = 14;

/// The Milestones strip: fixed squares scrolling sideways, exactly as the
/// rings do. Four fit the content width, so a collage of more than four is
/// reached by dragging rather than by shrinking every tile to suit.
const double _kStripTile = 80;
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

    final handle = ref.watch(currentProfileProvider).value?.username ?? '';
    // Read here, above the SafeArea that consumes it.
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      // No AppBar — the redundant "Profile" title is removed (matches Feed).
      // The readout is a QA overlay and a no-op in any normal build; see
      // PositionReadout.
      body: PositionReadout(
        title: 'PROFILE',
        targets: () => [
          ReadoutTarget('emblem   ', probeType('ProgressRing')),
          if (handle.isNotEmpty) ReadoutTarget('handle   ', probeText(handle)),
          ReadoutTarget('subtitle ', probeText('milestone')),
          ReadoutTarget('figures  ', probeType('_EffortSummary')),
          ReadoutTarget('hairline1', probeHairline()),
          ReadoutTarget('Friends  ', probeText('Friends')),
          ReadoutTarget('hairline2', probeHairline(), index: 1),
          ReadoutTarget('Mstones  ', probeText('Milestones')),
          ReadoutTarget('strip    ', probeType('_GalleryThumb')),
          ReadoutTarget('hairline3', probeHairline(), index: 2),
          ReadoutTarget('InProg   ', probeText('In progress')),
          ReadoutTarget('ringRow  ', probeType('_TaskTile')),
          // The first tile's name, which is the line this page's bottom edge
          // is specified in.
          if (tasks.isNotEmpty)
            ReadoutTarget('ringLabel', probeText(tasks.first.name)),
        ],
        child: SafeArea(
        // The viewport, measured. Everything about where the fold falls comes
        // from this number rather than from a guess about the device.
        child: LayoutBuilder(
          builder: (context, viewport) {
            // The pin exists to put the ring labels on Home's line. With no
            // ring row there is no label to pin, and pinning anyway is what
            // inflated the hero on a guest's page: the same target height,
            // a third less content, and two flexible gaps to swallow the
            // difference.
            // Whether the pin is worth having is decided at layout time,
            // from the column's measured height — see [_FirstScreen]. All
            // that is settled here is whether there is a label to aim at.
            final canPin = tasks.isNotEmpty;
            // Floor, then up to the ceiling — and no further. A LOOSE
            // Flexible takes min(its child, its share), so the gap is
            // clamped to [_kHeroGapMin, _kHeroGapMax] by the layout rather
            // than by arithmetic, and the share it declines stays in the
            // column's remaining space. Start-aligned, that remainder
            // collects after the last child: the bottom of the first screen.
            final heroGap = [
              SizedBox(height: _kHeroGapMin * scale),
              Flexible(
                child: _CappedSlack((_kHeroGapMax - _kHeroGapMin) * scale),
              ),
            ];

            return SingleChildScrollView(
            // Clamping, not bouncing. The page genuinely runs past the
            // viewport now; on iOS a bounce at the top of a page this
            // deliberately composed reads as slack.
            physics: const ClampingScrollPhysics(),
            // NO blanket horizontal padding. The gutter is applied per child
            // instead, so the two scrollers can span the whole screen while
            // the headings and hairlines stay in the content box.
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
                  _FirstScreen(
                    pin: _firstScreenHeight(context, topInset),
                    viewport: viewport.maxHeight,
                    gapFloor: _kHeroGapMin * scale,
                    gapCeiling: _kHeroGapMax * scale,
                    gapUnpinned: _kHeroGapFixed * scale,
                    canPin: canPin,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: _kTopMargin * scale),
                        const _Gutter(child: _HeroEmblem()),
                        // The two flexible gaps, either side of the
                        // handle-and-subtitle pair. Siblings in ONE column,
                        // because flex only equalises siblings — which is
                        // why the pair is its own widget rather than the
                        // hero being one block with a gap inside it.
                        ...heroGap,
                        const _Gutter(child: _HeroCaption()),
                        ...heroGap,
                        _Gutter(
                          child: _EffortSummary(
                            lifetime: lifetime,
                            streak: streak,
                            milestones: milestones,
                          ),
                        ),
                        SizedBox(height: _kBreak * scale),
                        const _Gutter(child: _Hairline()),
                        SizedBox(height: _kUnderHairline * scale),
                        const _Gutter(child: _FriendsRow()),
                        SizedBox(height: _kBreak * scale),
                        const _Gutter(child: _Hairline()),
                        SizedBox(height: _kUnderHairline * scale),
                        // Its heading keeps the gutter; its strip does not.
                        const _MilestonesRow(),
                        SizedBox(height: _kBreak * scale),
                        const _Gutter(child: _Hairline()),
                        SizedBox(height: _kUnderHairline * scale),
                        _TasksInProgress(tasks: tasks),
                        SizedBox(height: _kTabClearance * scale),
                      ],
                    ),
                  ),
                  // BELOW THE FOLD. Signed in, the email, Sign out and the
                  // QA word — things you go looking for, never the first
                  // thing the page offers.
                  const _Gutter(child: _Section(child: AccountBody())),
                  SizedBox(height: kSpacingBase * scale),
                ],
              ),
            );
          },
        ),
        ),
      ),
    );
  }
}

/// The style the ring labels are set in, shared so the pin below can measure
/// a line of it without rendering one.
TextStyle? nameStyleOf(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: _kRingLabelSize * figmaScale(context),
      fontWeight: FontWeight.w600,
      color: GreyscaleTokens.of(context).textSecondary,
    );

/// The height the first screen must be for the ring labels to sit on Home's
/// "View your progress" line.
///
/// Read downward from the label's CENTRE, which is the thing being pinned:
/// below it there is only its own lower half and the clearance to the tab bar.
/// Everything above it is fixed except the two hero gaps, so they take the
/// difference — see [_kHeroGapMin].
double _firstScreenHeight(BuildContext context, double columnTop) {
  final scale = figmaScale(context);
  final label = lineHeightOf(context, nameStyleOf(context), _kRingLabelSize);
  // [homeCtaCentreY] is a SCREEN y; this is a height measured from the
  // column's own top, which is [columnTop] below the top of the screen. It
  // has to be read ABOVE the page's SafeArea — inside it, both padding and
  // viewPadding have already been consumed and read as zero.
  return homeCtaCentreY(context) -
      columnTop +
      label / 2 +
      _kTabClearance * scale;
}

/// The first screen, sized by whether the pin can land without opening a void.
///
/// The pin puts the ring labels on Home's "View your progress" line by handing
/// the hero's two flexible gaps whatever the target height leaves over. That
/// is a couple of points on a full page and a hundred on a sparse one, so the
/// pin is only worth having when the gaps it asks for are gaps: at most
/// [gapCeiling]. Past that the page is better off unpinned, with the hero at
/// [gapUnpinned] and the slack at the foot.
///
/// The decision needs the column's natural height, which is not calculable in
/// a build method — it depends on which sections this account has — so it is
/// MEASURED here, as the child's intrinsic height. [_CappedSlack] reports zero
/// so that number is the column with both gaps at their floor, which is
/// exactly what the comparison needs.
class _FirstScreen extends SingleChildRenderObjectWidget {
  const _FirstScreen({
    required this.pin,
    required this.viewport,
    required this.gapFloor,
    required this.gapCeiling,
    required this.gapUnpinned,
    required this.canPin,
    required Widget super.child,
  });

  /// The height that lands the labels on Home's line.
  final double pin;

  /// The scroll viewport, so the account block starts past the bottom edge
  /// whichever way the decision goes.
  final double viewport;

  final double gapFloor;
  final double gapCeiling;
  final double gapUnpinned;

  /// False when there is no ring row — no label to pin, so nothing to aim at.
  final bool canPin;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFirstScreen(
    pin: pin,
    viewport: viewport,
    gapFloor: gapFloor,
    gapCeiling: gapCeiling,
    gapUnpinned: gapUnpinned,
    canPin: canPin,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderFirstScreen renderObject,
  ) {
    renderObject.configure(
      pin: pin,
      viewport: viewport,
      gapFloor: gapFloor,
      gapCeiling: gapCeiling,
      gapUnpinned: gapUnpinned,
      canPin: canPin,
    );
  }
}

class _RenderFirstScreen extends RenderShiftedBox {
  _RenderFirstScreen({
    required this.pin,
    required this.viewport,
    required this.gapFloor,
    required this.gapCeiling,
    required this.gapUnpinned,
    required this.canPin,
  }) : super(null);

  double pin;
  double viewport;
  double gapFloor;
  double gapCeiling;
  double gapUnpinned;
  bool canPin;

  /// One entry point for all six, so a changed number can never be applied
  /// without the relayout that has to follow it.
  void configure({
    required double pin,
    required double viewport,
    required double gapFloor,
    required double gapCeiling,
    required double gapUnpinned,
    required bool canPin,
  }) {
    if (pin == this.pin &&
        viewport == this.viewport &&
        gapFloor == this.gapFloor &&
        gapCeiling == this.gapCeiling &&
        gapUnpinned == this.gapUnpinned &&
        canPin == this.canPin) {
      return;
    }
    this.pin = pin;
    this.viewport = viewport;
    this.gapFloor = gapFloor;
    this.gapCeiling = gapCeiling;
    this.gapUnpinned = gapUnpinned;
    this.canPin = canPin;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      child?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      child?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    final width = constraints.maxWidth;
    // The column with both flexible gaps at their floor.
    final natural = child.getMaxIntrinsicHeight(width);
    // What each gap would have to grow to for the labels to land on the line.
    final wanted = gapFloor + (pin - natural) / 2;
    final pinned = canPin && wanted <= gapCeiling;
    // Pinned, the column is the target (or its own height, when the text is
    // big enough that the target is already too small — the yield).
    // Unpinned, it is its natural height with both gaps opened to their
    // fixed figure, and everything else becomes slack at the foot.
    final height = pinned
        ? math.max(pin, natural)
        : natural + 2 * (gapUnpinned - gapFloor);
    child.layout(
      BoxConstraints.tightFor(width: width, height: height),
      parentUsesSize: true,
    );
    (child.parentData! as BoxParentData).offset = Offset.zero;
    // At least the viewport, so the account block is always past the fold.
    size = constraints.constrain(Size(width, math.max(height, viewport)));
  }
}

/// Flexible space that takes up to [cap] of whatever it is offered, and asks
/// for NOTHING when the column is measured.
///
/// Both halves matter. A `Flexible` around a `SizedBox(height: cap)` caps the
/// gap correctly but reports the cap as its intrinsic height, and the first
/// screen is sized by [IntrinsicHeight] — so the page grew by the two caps
/// and the ring labels dropped 28 below Home's line. A cap is a limit on
/// space offered, never a request for it, which is what these zero intrinsics
/// say.
class _CappedSlack extends LeafRenderObjectWidget {
  const _CappedSlack(this.cap);

  final double cap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCappedSlack(cap);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderCappedSlack renderObject,
  ) {
    renderObject.cap = cap;
  }
}

class _RenderCappedSlack extends RenderBox {
  _RenderCappedSlack(this._cap);

  double _cap;
  set cap(double value) {
    if (value == _cap) return;
    _cap = value;
    markNeedsLayout();
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;
  @override
  double computeMaxIntrinsicWidth(double height) => 0;
  @override
  double computeMinIntrinsicHeight(double width) => 0;
  @override
  double computeMaxIntrinsicHeight(double width) => 0;

  @override
  void performLayout() {
    // Whatever is offered, up to the cap. What it declines stays in the
    // column's remaining space, which a start-aligned Column leaves after
    // its last child.
    size = constraints.constrain(
      Size(0, math.min(_cap, constraints.maxHeight)),
    );
  }
}

/// The page's content margin, applied per child.
///
/// It is not on the page's column, because the two horizontal scrollers have
/// to span the whole screen; everything else is wrapped in this instead.
class _Gutter extends StatelessWidget {
  const _Gutter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: _kGutter * figmaScale(context)),
    child: child,
  );
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

  /// Ø128, with the photo at the share it was measured at on the 132 ring:
  /// a 104 photo becomes ≈100.8 here, ≈80% of the outer diameter, which is
  /// what stops the ring reading as a thick frame.
  ///
  /// The stroke is the app's one ring weight rather than this ring's own
  /// share. It grows INWARD — the painter insets by half the stroke — so the
  /// outer diameter and the photo are where they were.
  static const double _ring = _kEmblemSize;
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
    final galleryAsync = ref.watch(galleryPreviewProvider);
    final recent = galleryAsync.value ?? const <Photo>[];
    final newest = recent.isEmpty ? null : recent.first;
    // Until the newest photo is known, the disc is a fixed, quiet surface —
    // the same size and tone as the photo's own placeholder — never the
    // initial, which is an answer ("there is no photo") the frame does not
    // yet have.
    final heroKnown = galleryAsync.hasValue;

    return Column(
      children: [
        ProgressRing(
          size: _ring * scale,
          stroke: ringStroke(scale),
          // An empty grey track when there is nothing to climb, and never a
          // closed one: see [shownProgress].
          progress: shownProgress(next?.progress ?? 0),
          center: SizedBox(
            width: _photo * scale,
            height: _photo * scale,
            child: !heroKnown
                ? ClipOval(child: ColoredBox(color: tokens.surface))
                : newest == null
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
      ],
    );
  }
}

/// The handle and the line under it, as ONE block.
///
/// They are a pair: a name and what the name is doing. The gap between them
/// is 4 — tighter than anything else on the page, which is the whole point of
/// a pair — and the flexible air sits OUTSIDE the pair, above the handle and
/// below the line. Air between them is what made the subtitle read as a
/// separate thing that happened to be nearby.
class _HeroCaption extends ConsumerWidget {
  const _HeroCaption();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    final next = ref.watch(nextMilestoneProvider);
    final handle = ref.watch(currentProfileProvider).value?.username ?? '';
    final quiet = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 13 * scale,
      color: tokens.textSecondary,
    );

    return Column(
      children: [
        // The person, at the top of their own page at last. Omitted rather
        // than faked when there is no handle yet — the account block below
        // still offers to set one.
        if (handle.isNotEmpty) ...[
          Text(
            // No "@". This is your own page — the handle is your name here,
            // not a mention of you, the same reading the friends list takes.
            handle,
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
/// crossed milestones beneath it — one photo per milestone, the most recently
/// crossed first.
///
/// Borderless like Friends. The heading opens the page on its default lens —
/// the row is always here, so the Photos lens is one tab away once you
/// arrive. A photo in the strip opens the viewer on that photo, with the
/// rest of its stretch a swipe away.
///
/// The COUNT is [milestonesReachedProvider], the same figure the totals above
/// show. It used to be the number of saved collages, which is a different
/// thing: a collage is written when a milestone is crossed with photos in its
/// band, so a milestone reached with nothing captured, or crossed before the
/// auto-compose existed, had no collage and went uncounted. The strip is
/// [milestoneStripProvider], one entry per crossed milestone that has a photo
/// to show; a milestone with none is counted and not pictured.
class _MilestonesRow extends ConsumerWidget {
  const _MilestonesRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    final n = ref.watch(milestonesReachedProvider);
    final strip = ref.watch(milestoneStripProvider).value ??
        const <MilestoneStripEntry>[];
    // Decode what the strip shows and what each of its stretches would show,
    // now, while Profile is on screen: the detail then paints from memory.
    if (strip.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        precachePhotos(context, [
          for (final e in strip) e.photo.photoUrl,
          for (final e in strip)
            for (final p in e.detail.photos) p.photoUrl,
        ]);
      });
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const MilestonesScreen())),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Gutter(
            child: Row(
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
          ),
          if (strip.isNotEmpty) ...[
            SizedBox(height: _kHeadingToPhotos * scale),
            // Full-bleed: the viewport is the screen, and the margin is the
            // scroller's own padding — so the first tile still starts on the
            // margin, and the last can be dragged to it instead of stopping
            // short of the edge.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const ClampingScrollPhysics(),
              padding: EdgeInsets.symmetric(horizontal: _kGutter * scale),
              child: Row(
                children: [
                  for (var i = 0; i < strip.length; i++) ...[
                    if (i > 0) SizedBox(width: _kStripGap * scale),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      // The photo itself, large, with the rest of its
                      // stretch a swipe away. The heading still opens the
                      // Milestones page.
                      onTap: () {
                        final set = bandViewerSet(strip[i].detail);
                        showPhotoViewer(
                          context,
                          photos: set,
                          index: viewerIndexOf(set, strip[i].photo),
                        );
                      },
                      child: _GalleryThumb(photo: strip[i].photo),
                    ),
                  ],
                ],
              ),
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
        _Gutter(
          child: Row(
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
              // rows above it. The same set the row scrolls through: tasks
              // not archived.
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
        ),
        SizedBox(height: _kHeadingToRings * scale),
        if (tasks.isEmpty)
          _Gutter(
            child: Text(
              'Start a task on the timer to see it climb here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontSize: 13 * scale,
                color: tokens.textSecondary,
              ),
            ),
          )
        else
          // EVERY task, scrolling sideways. About four fit and the fifth
          // peeks, so the row says it has more without having to grow; the
          // count beside the heading says how many more.
          //
          // A scroll view around a Row rather than a ListView: a ListView
          // needs its cross-axis extent declared, and the declared number was
          // a fraction under what the name's line actually measures, which
          // clipped it and reported an overflow. This takes its height from
          // the tiles, so the row is one tile tall whatever the count —
          // fixed, and measurable.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: _kGutter * scale),
            child: Row(
              children: [
                for (var i = 0; i < tasks.length; i++) ...[
                  if (i > 0) SizedBox(width: _kRingGap * scale),
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

  /// The Milestones page's own task ring — Ø56 at the shared thin stroke (see
  /// _DoneRing in milestones_screen.dart), so a ring is the same size and the
  /// same weight on both screens. The TONE is not shared: this one is
  /// progress, so it stays grey, and white remains a milestone reached.
  static const double ringSize = 56;
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
    final nameStyle = nameStyleOf(context);

    return SizedBox(
      width: _kRingTileWidth * scale,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: ProgressRing(
              size: ringSize * scale,
              // The app's one ring weight, not a fraction of this ring's
              // diameter — see [kRingStroke].
              stroke: ringStroke(scale),
              // Progress through the CURRENT 20h block, so the ring keeps
              // climbing toward the next milestone rather than pinning full
              // — and clamped, so a first session shows and a last hour
              // doesn't read as finished.
              progress: shownProgress(task.milestoneProgress),
              // The TARGET, not the total: the figure names the thing the
              // ring is filling toward, which is what the ring is about.
              // Lifetime hours are up in the figures at the top of the page.
              center: Text(
                '${task.activeMilestoneHours}h',
                style: figureStyle,
              ),
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
      ),
    );
  }
}

/// One photo in the milestones strip — a fixed square, with the near-raw tint
/// and a muted tile rather than a broken image when a URL fails.
class _GalleryThumb extends StatelessWidget {
  const _GalleryThumb({required this.photo});

  final Photo photo;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    return SizedBox(
      width: _kStripTile * scale,
      height: _kStripTile * scale,
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

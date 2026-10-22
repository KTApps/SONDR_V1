import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/cached_photo.dart';
import '../timer/home_metrics.dart';

/// The Profile page's measurements, in one place, because a second profile
/// now uses them.
///
/// Every number here was calibrated on the Profile tab (see the long notes
/// in profile_screen.dart, which reads them from here): the hero's geometry,
/// the section rhythm, the type sizes and the strip's tiles. Another
/// person's profile is the same page about somebody else, so it takes the
/// same numbers rather than numbers that merely look like them.
/// The page's horizontal content margin.
const double kProfileGutter = 24;

/// Air above the emblem.
const double kProfileTopMargin = 46;

/// The hero ring, and the photo inside it — the photo at the share it was
/// measured at on the 132 ring, which is what stops the ring reading as a
/// thick frame.
const double kProfileEmblemSize = 128;
const double kProfileEmblemPhoto = kProfileEmblemSize * 104 / 132;

/// Emblem to handle, with no pin to satisfy. Between the floor and the
/// ceiling, and fixed, because without something to line up with at the
/// bottom there is no reason for the hero to stretch at all.
const double kProfileHeroGap = 18;

/// The FLOOR on each of the two flexible hero gaps.
///
/// They are equal and flexible — ABOVE the handle and BELOW the subtitle,
/// which is to say either side of the pair, never between them. The first
/// screen's height is pinned, and these two are the only gaps that give,
/// splitting whatever the pin leaves over. 16 is the tightest either may
/// become.
///
/// Flex is here, which the rest of the page forbids, and the difference is
/// the pin: an Expanded with nothing below it to stop against is what
/// pooled the slack into a void last time. Here the bottom is fixed by a
/// target, so there is a bounded amount to share and exactly two places for
/// it to go.
const double kProfileHeroGapMin = 16;

/// The floor on the hero gaps of a profile ABOUT SOMEBODY ELSE.
///
/// Lower than [kProfileHeroGapMin], and it has to be. That page ends on a
/// photo strip — a heading, 26, and an 80 tile — where the personal
/// Profile ends on a ring row, a heading, 20, and a 78 tile. Seven points
/// more content, in a first screen pinned to the same line, and the hero
/// gaps are the only thing that gives: held at 16 the page cannot make the
/// line at all, and misses it by those seven points.
///
/// 12 is [kSpacingPair], the tightest gap in the ladder, and it leaves the
/// pair the same air a pair gets anywhere else. The ceiling is unchanged,
/// so a sparse page still opens up exactly as the personal one does.
const double kProfileOtherHeroGapMin = 12;

/// The CEILING on each flexible gap.
///
/// 32 is the void threshold the composition has always been checked
/// against; past it a gap stops reading as spacing and starts reading as a
/// page that has run out of things to say. The gaps hit it on a sparse page
/// — a guest with no tasks and no milestones has a third less content for
/// the same pinned height — and on the device they reached 117, which put
/// the ring and the line under it at opposite ends of the screen.
///
/// The slack past the ceiling goes to the BOTTOM of the first screen, below
/// the last section, where empty space at the end reads as the end of the
/// page rather than as a hole in the middle of it.
const double kProfileHeroGapMax = 32;

/// The ring labels' own size — the line the first screen is pinned by.
const double kProfileRingLabelSize = 11;

/// What is left below the last element: the clearance to the tab bar, and
/// the only gap that can give once the emblem and the top margin are
/// spent. It is also what the two profiles have in common at the bottom —
/// the last thing on each first screen ends this far above its foot, which
/// is what lands them on the same line.
const double kProfileTabClearance = 16;

/// Handle to the line under it: a PAIR gap, the tightest on the page.
const double kProfileHandleToSubline = 4;

/// The stats' figures, their labels, and the gap between the two.
const double kProfileStatFigureSize = 22;
const double kProfileStatLabelSize = 12;
const double kProfileStatGap = 5;

/// A section break: this much above the hairline, and
/// [kProfileUnderHairline] below it. Deliberately unequal, so a heading
/// hugs the content it introduces instead of floating between two sections.
const double kProfileBreak = 22;
const double kProfileUnderHairline = 14;

/// A heading to the strip beneath it.
const double kProfileHeadingToPhotos = 26;

/// Section headings take the app's Heading token — the same 20/bold Home
/// puts on "Last 10 days" — and the counts beside them this.
const double kProfileHeadingSize = 20;
const double kProfileCountSize = 14;

/// The hairline. Darker than [GreyscaleTokens.ringTrack], which is a RING
/// tone: a rule between sections should part them without being read as one
/// more thing on the page.
const Color kProfileHairline = Color(0xFF242424);

/// Photo tints — the near-raw whisper the day-detail thumbnails use, so
/// every photo surface sits in the same family.
const double kProfilePhotoSaturation = 0.85;
const Color kProfilePhotoTint = Color(0x1A000000);

/// The strips: fixed squares scrolling sideways. Four fit the content width,
/// so a fifth is reached by dragging rather than by shrinking every tile.
const double kProfileStripTile = 80;
const double kProfileStripGap = 8;
const double kProfileStripRadius = 13;

/// One tile in a strip: a fixed square, rounded, at the page's photo tone.
class ProfileStripTile extends StatelessWidget {
  const ProfileStripTile({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    return SizedBox(
      width: kProfileStripTile * scale,
      height: kProfileStripTile * scale,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kProfileStripRadius * scale),
        child: SondrPhoto(
          url: url,
          saturation: kProfilePhotoSaturation,
          tint: kProfilePhotoTint,
          placeholder: (_) => ColoredBox(color: tokens.ringTrack),
          error: (_) => ColoredBox(color: tokens.ringTrack),
        ),
      ),
    );
  }
}

/// The page's gutter, applied.
class ProfileGutter extends StatelessWidget {
  const ProfileGutter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
    padding:
        EdgeInsets.symmetric(horizontal: kProfileGutter * figmaScale(context)),
    child: child,
  );
}

/// One of the figures under the hero: the number, then what it counts.
class ProfileStat extends StatelessWidget {
  const ProfileStat({super.key, required this.value, required this.label});

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
            fontSize: kProfileStatFigureSize * scale,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
        SizedBox(height: kProfileStatGap * scale),
        Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: kProfileStatLabelSize * scale,
            color: tokens.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// A section heading, with its count beside it. Borderless and tappable
/// where it leads somewhere — a rounded fill reads as a button, and a
/// chevron is a second vocabulary for what a row already says (DESIGN.md).
///
/// A count of zero is left off: it tells the reader nothing and costs a
/// number.
class ProfileHeading extends StatelessWidget {
  const ProfileHeading({
    super.key,
    required this.label,
    this.count,
    this.onTap,
  });

  final String label;

  /// Already formatted, so a capped count can read "100+".
  final String? count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final row = Row(
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: kProfileHeadingSize * scale,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
        const Spacer(),
        if (count != null)
          Text(
            count!,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: kProfileCountSize * scale,
              fontWeight: FontWeight.w700,
              color: tokens.textTertiary,
            ),
          ),
      ],
    );
    if (onTap == null) return row;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: row,
    );
  }
}

/// The line between sections.
class ProfileHairline extends StatelessWidget {
  const ProfileHairline({super.key});

  @override
  Widget build(BuildContext context) =>
      const SizedBox(height: 1, child: ColoredBox(color: kProfileHairline));
}

/// The style the ring labels are set in, shared so the pin below can measure
/// a line of it without rendering one.
TextStyle? profileRingLabelStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: kProfileRingLabelSize * figmaScale(context),
      fontWeight: FontWeight.w600,
      color: GreyscaleTokens.of(context).textSecondary,
    );

/// The height the first screen must be for the ring labels to sit on Home's
/// "View your progress" line.
///
/// Read downward from the label's CENTRE, which is the thing being pinned:
/// below it there is only its own lower half and the clearance to the tab bar.
/// Everything above it is fixed except the two hero gaps, so they take the
/// difference — see [kProfileHeroGapMin].
double profileFirstScreenHeight(BuildContext context, double columnTop) {
  final scale = figmaScale(context);
  final label = lineHeightOf(context, profileRingLabelStyle(context), kProfileRingLabelSize);
  // [homeCtaCentreY] is a SCREEN y; this is a height measured from the
  // column's own top, which is [columnTop] below the top of the screen. It
  // has to be read ABOVE the page's SafeArea — inside it, both padding and
  // viewPadding have already been consumed and read as zero.
  return homeCtaCentreY(context) -
      columnTop +
      label / 2 +
      kProfileTabClearance * scale;
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
class ProfileFirstScreen extends SingleChildRenderObjectWidget {
  const ProfileFirstScreen({
    super.key,
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
  RenderObject createRenderObject(BuildContext context) => _RenderProfileFirstScreen(
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
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderProfileFirstScreen)
        .configure(
      pin: pin,
      viewport: viewport,
      gapFloor: gapFloor,
      gapCeiling: gapCeiling,
      gapUnpinned: gapUnpinned,
      canPin: canPin,
    );
  }
}

class _RenderProfileFirstScreen extends RenderShiftedBox {
  _RenderProfileFirstScreen({
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
class ProfileCappedSlack extends LeafRenderObjectWidget {
  const ProfileCappedSlack(this.cap, {super.key});

  final double cap;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderProfileCappedSlack(cap);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderObject renderObject,
  ) {
    (renderObject as _RenderProfileCappedSlack).cap = cap;
  }
}

class _RenderProfileCappedSlack extends RenderBox {
  _RenderProfileCappedSlack(this._cap);

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

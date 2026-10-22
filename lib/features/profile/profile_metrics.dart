import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/cached_photo.dart';

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

/// Emblem to handle.
const double kProfileHeroGap = 18;

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

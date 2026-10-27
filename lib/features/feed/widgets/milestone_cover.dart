import 'package:flutter/material.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../collage_layout.dart';
import 'milestone_frame.dart';
import 'milestone_ring.dart';

/// The milestone's cover: its photos tiled as a collage, the scrim, and the
/// solid ring with the hours in it. One picture, drawn here for the feed
/// when a post has no rendered cover, for the Profile strip and the
/// Milestones page, and — by the same figures, on a canvas — at share time.

/// The collage alone: [photos] tiled in a box, oldest first, each
/// cover-cropped and framed. Fills whatever box it is given.
class MilestoneCollage extends StatelessWidget {
  const MilestoneCollage({
    super.key,
    required this.photos,
    this.framings,
    this.gap = kCollageGap,
  });

  final List<ImageProvider> photos;

  /// One per photo, or null for the plain cover crop throughout.
  final List<PhotoFraming>? framings;

  final double gap;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final shown = photos.take(kCollageMax).toList();
    return LayoutBuilder(
      builder: (context, c) {
        final tiles = collageTiles(Size(c.maxWidth, c.maxHeight), shown.length, gap: gap);
        return ColoredBox(
          color: tokens.surface,
          child: Stack(
            children: [
              for (var i = 0; i < tiles.length; i++)
                Positioned.fromRect(
                  rect: tiles[i],
                  child: FramedPhoto(
                    image: shown[i],
                    framing: framings != null && i < framings!.length
                        ? framings![i]
                        : PhotoFraming.none,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One photo cover-cropped into its box, zoomed and nudged by [framing].
class FramedPhoto extends StatelessWidget {
  const FramedPhoto({
    super.key,
    required this.image,
    this.framing = PhotoFraming.none,
  });

  final ImageProvider image;
  final PhotoFraming framing;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final photo = Image(
      image: image,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => ColoredBox(color: tokens.surface),
    );
    if (framing == PhotoFraming.none) return ClipRect(child: photo);
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, c) => Transform.translate(
          offset: Offset(framing.dx * c.maxWidth, framing.dy * c.maxHeight),
          child: Transform.scale(scale: framing.scale, child: photo),
        ),
      ),
    );
  }
}

/// The cover, complete: the collage under the scrim under the ring. Drawn
/// at the reference frame size and scaled to fill its box, so a thumbnail
/// is the same picture small — and the same picture the rendered cover is.
class MilestoneCover extends StatelessWidget {
  const MilestoneCover({
    super.key,
    required this.photos,
    required this.milestoneHours,
    this.framings,
  });

  final List<ImageProvider> photos;
  final int milestoneHours;
  final List<PhotoFraming>? framings;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox.fromSize(
        size: kMilestoneFrameSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MilestoneCollage(photos: photos, framings: framings),
            const DecoratedBox(
              decoration: BoxDecoration(gradient: kMilestoneScrim),
            ),
            Positioned(
              top: milestoneRingTop(kMilestoneFrameSize.height),
              left: (kMilestoneFrameSize.width - kMilestoneRingSize) / 2,
              child: MilestoneRing(
                onPhoto: true,
                center: MilestoneRingCentre(
                  figure: '$milestoneHours',
                  unit: 'hours',
                  onPhoto: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

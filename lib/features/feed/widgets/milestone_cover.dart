import 'package:flutter/material.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../shared/cached_photo.dart';
import '../collage_layout.dart';
import 'milestone_frame.dart';
import 'milestone_ring.dart';

/// The milestone's cover: its photos tiled as a collage, the scrim, and the
/// solid ring with the hours in it. One picture, drawn here for the feed
/// when a post has no rendered cover, for the Profile strip and the
/// Milestones page, and — by the same figures, on a canvas — at share time.

/// The collage alone: [photos] tiled in a box of [size], oldest first,
/// each cover-cropped and framed. The size is given, not measured: the
/// Profile page measures its first screen by intrinsics, which a
/// LayoutBuilder cannot answer.
class MilestoneCollage extends StatelessWidget {
  const MilestoneCollage({
    super.key,
    required this.photos,
    required this.size,
    this.framings,
    this.gap = kCollageGap,
  });

  final List<ImageProvider> photos;
  final Size size;

  /// One per photo, or null for the plain cover crop throughout.
  final List<PhotoFraming>? framings;

  final double gap;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final shown = photos.take(kCollageMax).toList();
    final tiles = collageTiles(size, shown.length, gap: gap);
    return SizedBox.fromSize(
      size: size,
      child: ColoredBox(
        color: tokens.surface,
        child: Stack(
          children: [
            for (var i = 0; i < tiles.length; i++)
              Positioned.fromRect(
                rect: tiles[i],
                child: FramedPhoto(
                  image: shown[i],
                  size: tiles[i].size,
                  framing: framings != null && i < framings!.length
                      ? framings![i]
                      : PhotoFraming.none,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One photo cover-cropped into a tile of [size], zoomed and nudged by
/// [framing].
class FramedPhoto extends StatelessWidget {
  const FramedPhoto({
    super.key,
    required this.image,
    required this.size,
    this.framing = PhotoFraming.none,
  });

  final ImageProvider image;
  final Size size;
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
      child: Transform.translate(
        offset: Offset(framing.dx * size.width, framing.dy * size.height),
        child: Transform.scale(scale: framing.scale, child: photo),
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
            MilestoneCollage(
              photos: photos,
              size: kMilestoneFrameSize,
              framings: framings,
            ),
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

/// The cover in a small box — a strip tile, a row's thumb: the rendered
/// cover when the milestone was shared with one, else the collage drawn
/// from its photos. Cover-cropped into whatever box it is given.
class MilestoneCoverTile extends StatelessWidget {
  const MilestoneCoverTile({
    super.key,
    required this.milestoneHours,
    required this.photoUrls,
    this.framings,
    this.coverUrl,
    this.saturation,
    this.tint,
  });

  final int milestoneHours;

  /// The collage's photos, oldest first, for the drawn cover.
  final List<String> photoUrls;

  /// How each is framed in its tile, when the author set it.
  final List<PhotoFraming>? framings;

  /// The rendered cover, when there is one.
  final String? coverUrl;

  /// The surface's own treatment of a photo, applied to a rendered cover.
  final double? saturation;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final cover = coverUrl;
    if (cover != null && cover.isNotEmpty) {
      return SondrPhoto(
        url: cover,
        saturation: saturation,
        tint: tint,
        placeholder: (_) => ColoredBox(color: tokens.ringTrack),
        error: (_) => ColoredBox(color: tokens.ringTrack),
      );
    }
    return MilestoneCover(
      photos: [
        for (final url in photoUrls)
          if (url.isNotEmpty) cachedPhotoProvider(url),
      ],
      framings: framings,
      milestoneHours: milestoneHours,
    );
  }
}

/// The milestone in a strip or a row's thumb: the collage alone — no
/// ring, no scrim, no text — as the thumbnail rendered at share time, else
/// drawn from the photos. Cover-cropped into whatever box it is given.
class MilestoneCollageThumb extends StatelessWidget {
  const MilestoneCollageThumb({
    super.key,
    required this.photoUrls,
    this.framings,
    this.thumbUrl,
    this.saturation,
    this.tint,
  });

  /// The collage's photos, oldest first, for the drawn collage.
  final List<String> photoUrls;

  /// How each is framed in its tile, when the author set it.
  final List<PhotoFraming>? framings;

  /// The rendered thumbnail, when there is one.
  final String? thumbUrl;

  /// The surface's own treatment of a photo, applied to a rendered thumbnail.
  final double? saturation;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final thumb = thumbUrl;
    if (thumb != null && thumb.isNotEmpty) {
      return SondrPhoto(
        url: thumb,
        saturation: saturation,
        tint: tint,
        placeholder: (_) => ColoredBox(color: tokens.ringTrack),
        error: (_) => ColoredBox(color: tokens.ringTrack),
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: MilestoneCollage(
        photos: [
          for (final url in photoUrls)
            if (url.isNotEmpty) cachedPhotoProvider(url),
        ],
        framings: framings,
        size: kMilestoneFrameSize,
      ),
    );
  }
}

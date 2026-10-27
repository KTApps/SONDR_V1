import 'package:flutter/material.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../photos/capture_crop.dart';
import 'milestone_ring.dart';

/// The shape every milestone frame shares, with or without a photo: the
/// 3:4 frame, where the ring sits, and the scrim over a photo.

/// Where the ring's centre sits: 44% of the way down the frame.
const double kMilestoneRingCentre = 0.44;

/// The ring's top edge in a frame [height] tall.
double milestoneRingTop(double height, {double size = kMilestoneRingSize}) =>
    height * kMilestoneRingCentre - size / 2;

/// The frame's width on the reference phone — the card at the iPhone 13
/// Pro's width, inside the feed's gutter. The cover image and every
/// thumbnail are the same picture drawn at this size and scaled.
const double kMilestoneFrameWidth = 358;
const Size kMilestoneFrameSize = Size(
  kMilestoneFrameWidth,
  kMilestoneFrameWidth / kCaptureAspect,
);

/// The scrim over a photo: darker at the top where the handle sits and at
/// the bottom under the task and the actions; clear through the middle
/// where the ring is. Each end eases through several stops rather than
/// running straight to nothing: a straight run ends in a visible edge on a
/// flat, bright photo.
const LinearGradient kMilestoneScrim = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0x73000000), // 45%
    Color(0x4D000000), // 30%
    Color(0x24000000), // 14%
    Color(0x0D000000), // 5%
    Color(0x00000000),
    Color(0x00000000),
    Color(0x0F000000), // 6%
    Color(0x33000000), // 20%
    Color(0x6B000000), // 42%
    Color(0xB3000000), // 70%
  ],
  stops: [0, 0.065, 0.13, 0.195, 0.26, 0.54, 0.655, 0.77, 0.885, 1],
);

/// The frame with no photo in it: the surface, and the ring with the hours
/// in it where the card's ring always is — no scrim, nothing to hold back.
/// The card's no-photo page, and what the share review shows for a
/// milestone posted without a photo.
class MilestoneNoPhotoFrame extends StatelessWidget {
  const MilestoneNoPhotoFrame({super.key, required this.milestoneHours});

  final int? milestoneHours;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    return ColoredBox(
      color: tokens.surface,
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            Positioned(
              top: milestoneRingTop(c.maxHeight),
              left: (c.maxWidth - kMilestoneRingSize) / 2,
              child: MilestoneRing(
                onPhoto: false,
                center: MilestoneRingCentre(
                  figure: '${milestoneHours ?? ''}',
                  unit: 'hours',
                  onPhoto: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

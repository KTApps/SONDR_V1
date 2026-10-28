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

/// The scrim over a photo: a light top under the handle, 28% easing to
/// nothing over the first 24%; clear through the middle; and the bottom
/// under the task and the actions, nothing to 18% to 45% over the last
/// 38%. Each end eases through several stops rather than running
/// straight: a straight run ends in a visible band on a flat, bright
/// photo.
const LinearGradient kMilestoneScrim = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [
    Color(0x47000000), // 28%
    Color(0x36000000), // 21%
    Color(0x1F000000), // 12%
    Color(0x0A000000), // 4%
    Color(0x00000000), // 0 at 24%
    Color(0x00000000), // 0 at 62%
    Color(0x0F000000), // 6%
    Color(0x2E000000), // 18% at 81%
    Color(0x4F000000), // 31%
    Color(0x73000000), // 45%
  ],
  stops: [0, 0.06, 0.12, 0.18, 0.24, 0.62, 0.715, 0.81, 0.905, 1],
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

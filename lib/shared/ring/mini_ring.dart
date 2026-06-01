import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import 'ring_painter.dart';
import 'ring_palette.dart';

/// A small pie ring built on the same [RingPainter] as the hero dial, so the
/// visual language is identical at every scale. Used for the "last 10 days" row
/// (each ring is that day's task split) and tasks-in-progress on a profile.
class MiniRing extends StatelessWidget {
  const MiniRing({
    super.key,
    required this.segments,
    this.size = 36,
    this.child,
  });

  /// Per-task values for the day this ring represents. Empty or all-zero → the
  /// ring shows just its track.
  final List<double> segments;

  /// Diameter in logical pixels.
  final double size;

  /// Optional centre content (a tiny date number, an icon).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final colors = RingPalette.ramp(tokens, segments.length);
    final segs = <RingSegment>[
      for (var i = 0; i < segments.length; i++)
        RingSegment(
          value: segments[i] < 0 ? 0 : segments[i],
          color: colors[i],
        ),
    ];

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: RingPainter(
              layers: [
                SegmentRingLayer(
                  thickness: size * 0.13,
                  segments: segs,
                  track: tokens.ringTrack,
                ),
              ],
            ),
          ),
          ?child,
        ],
      ),
    );
  }
}

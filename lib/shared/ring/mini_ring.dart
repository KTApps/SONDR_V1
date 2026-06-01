import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import 'ring_painter.dart';

/// A small single-ring built on the same [RingPainter] as the hero dial, so the
/// visual language stays identical at every scale. Used for the "last 10 days"
/// row and the tasks-in-progress mini rings on a profile.
class MiniRing extends StatelessWidget {
  const MiniRing({
    super.key,
    required this.progress,
    this.size = 36,
    this.dimmed = false,
    this.child,
  });

  /// 0..1 portion filled.
  final double progress;

  /// Diameter in logical pixels.
  final double size;

  /// Use the dimmer (inner-ring) fill tone — e.g. for de-emphasised days.
  final bool dimmed;

  /// Optional centre content (a tiny date number, an icon).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
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
                RingLayer(
                  progress: progress.clamp(0.0, 1.0),
                  thickness: size * 0.13,
                  track: tokens.ringTrack,
                  fill: dimmed ? tokens.ringFillInner : tokens.ringFillOuter,
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

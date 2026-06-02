import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import 'ring_painter.dart';
import 'ring_palette.dart';

/// The signature component of Sondr: the dual-ring effort dial.
///
/// Built once and reused everywhere — home screen, feed cards, profiles — so it
/// stays self-contained and presentational. It renders against the greyscale
/// ladder:
///
///  * **Outer ring** = a proportional pie of how the day's time is split across
///    tasks. Each value in [taskSegments] is one task's time; segments are
///    sized by share. With [highlightedSegment] set (a specific task selected)
///    that slice is the brightest tone and the rest dim, so the day's whole
///    split stays visible while the selection stands out.
///  * **Inner ring** = daily habits completed today, [habitProgress] (0..1),
///    one step dimmer — fully independent of the task split.
///  * **Centre** = whatever [center] widget the caller supplies (the screen
///    owns the today/month figure and its gestures).
///
/// Set [onPhoto] over a photo backdrop: fills go near-white and the painter
/// adds contrast halos so the ring stays legible over any image.
class RingDial extends StatelessWidget {
  const RingDial({
    super.key,
    required this.taskSegments,
    this.highlightedSegment,
    required this.habitProgress,
    this.size = 280,
    this.onPhoto = false,
    this.center,
    this.onInnerRingTap,
  });

  /// Per-task values for the day (e.g. seconds logged today). Order is stable
  /// and matches [highlightedSegment]'s index. Empty → the ring shows just its
  /// track.
  final List<double> taskSegments;

  /// Index into [taskSegments] to emphasise (the selected task). Null renders
  /// the even collective ramp with nothing emphasised.
  final int? highlightedSegment;

  /// 0..1 — habits checked off today ÷ today's total habits.
  final double habitProgress;

  /// Overall diameter in logical pixels.
  final double size;

  /// Render the photo-backdrop variant (light fills + contrast halos).
  final bool onPhoto;

  /// Centre content (the screen builds the today/month figure here).
  final Widget? center;

  /// Called when the user taps the inner (habit) ring band. The centre figure
  /// is excluded, so its own gestures (e.g. the today/month swipe) are
  /// unaffected.
  final VoidCallback? onInnerRingTap;

  // Stroke widths scale with the dial so the component looks right at any size.
  double get _outerThickness => size * 0.090;
  double get _innerThickness => size * 0.074;

  /// True if [p] (local to the dial) falls within the inner ring's band, with a
  /// little tolerance so it's easy to hit. Mirrors the painter's geometry.
  bool _hitsInnerRing(Offset p) {
    final c = size / 2;
    final dist = (p - Offset(c, c)).distance;
    final gap = size * 0.035;
    final outerR = size / 2 - _outerThickness / 2;
    final innerR = outerR - _outerThickness / 2 - gap - _innerThickness / 2;
    final low = innerR - _innerThickness / 2 - 16;
    final high = innerR + _innerThickness / 2 + 16;
    return dist >= low && dist <= high;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final track =
        onPhoto ? Colors.white.withValues(alpha: 0.30) : tokens.ringTrack;
    final innerFill = onPhoto ? const Color(0xFFE6E6E6) : tokens.ringFillInner;

    final count = taskSegments.length;
    final colors = highlightedSegment != null
        ? RingPalette.highlighted(tokens, count, highlightedSegment!,
            onPhoto: onPhoto)
        : RingPalette.ramp(tokens, count, onPhoto: onPhoto);

    final segments = <RingSegment>[
      for (var i = 0; i < count; i++)
        RingSegment(
          value: taskSegments[i] < 0 ? 0 : taskSegments[i],
          color: colors[i],
        ),
    ];

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: onInnerRingTap == null
                ? null
                : (details) {
                    if (_hitsInnerRing(details.localPosition)) {
                      onInnerRingTap!();
                    }
                  },
            child: CustomPaint(
              size: Size.square(size),
              painter: RingPainter(
                onPhoto: onPhoto,
                layers: [
                  SegmentRingLayer(
                    thickness: _outerThickness,
                    segments: segments,
                    track: track,
                  ),
                  ProgressRingLayer(
                    thickness: _innerThickness,
                    progress: habitProgress.clamp(0.0, 1.0),
                    track: track,
                    fill: innerFill,
                  ),
                ],
              ),
            ),
          ),
          ?center,
        ],
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';
import 'ring_metrics.dart';

/// The app's data-driven dual ring (segmented, pure greyscale).
///
/// Distinct from [RingDial] (now used only by the feed's photo milestone
/// card): this one renders a day's live state as discrete segments cut by
/// slits.
///
///  * **Outer ring** = that day's time split across tasks. One segment per
///    task with time, arc length proportional to that time, in the PROGRESS
///    tone. One task → a full solid ring (no slit); no tasks → an empty track.
///    When a specific task is selected, its segment keeps the fill and the
///    rest drop to the track tone.
///  * **Inner ring** = that day's habits. One EQUAL segment per defined habit
///    (slits always present), filled WHITE when that habit is done and left as
///    track when it is not.
///
/// The two tones are the whole grammar: grey is in progress, white is reached.
/// A day's time is never "reached" — there is no target — so the outer ring is
/// always grey; a habit is binary, so it is always white or nothing.
///
/// Every band is stroked at [kThinRingStrokeRatio] of ITS OWN diameter, which
/// is what makes this dial the same pen as the profile emblem and the
/// Milestones rings at any size.
class SegmentedDial extends StatelessWidget {
  const SegmentedDial({
    super.key,
    required this.taskTodaySeconds,
    this.selectedTaskIndex,
    required this.habitStates,
    this.size = 260,
    this.compact = false,
    this.center,
    this.fill,
    this.onInnerRingTap,
  });

  /// Seconds logged on the day per task, in stable task order (zeros included).
  final List<double> taskTodaySeconds;

  /// Index into [taskTodaySeconds] of the selected task, or null for the
  /// collective ("all tasks") view.
  final int? selectedTaskIndex;

  /// Completion state of each *defined* habit that day (one entry per habit).
  final List<bool> habitStates;

  /// Overall diameter of the dial box.
  final double size;

  /// Use the smaller-circle proportions (Last-10-days / calendar minis): a
  /// tighter inner ring per the Figma mini (outer 50 / inner 28, extent 57).
  /// False → the main dial proportions.
  final bool compact;

  /// Centre content (the screen owns the today/month figure and its gestures).
  final Widget? center;

  /// Optional content composited inside the outer ring — circular-cropped to
  /// the ring's inner diameter and layered between the rings and [center].
  /// Used by the calendar to show a day's photo inside its effort ring.
  final Widget? fill;

  /// Tapped on the inner (habit) ring band.
  final VoidCallback? onInnerRingTap;

  // Both proportion sets scale fully with the box, so the radii and slit
  // shrink together and the circles look proportionally identical at any size:
  //  * main dial — outer 290 / inner 220 / slit 5 (extent 312)
  //  * compact   — outer 50 / inner 28 / slit 3.5 (extent 57)
  double get _outerRadius => size * (compact ? 25 / 57 : 145 / 312);
  double get _innerRadius => size * (compact ? 14 / 57 : 110 / 312);
  double get _slit => size * (compact ? 3.5 / 57 : 5 / 312);

  /// The diameter of each band — public so the weight rule can be asserted
  /// against the thing it is a fraction OF.
  double get outerDiameter => _outerRadius * 2;
  double get innerDiameter => _innerRadius * 2;

  /// Each band takes the thin ratio of its OWN diameter, so the inner band is
  /// proportionally as light as the outer one rather than looking heavier for
  /// being smaller.
  double get outerStroke => thinRingStroke(outerDiameter);
  double get innerStroke => thinRingStroke(innerDiameter);

  bool _hitsInnerRing(Offset p) {
    final c = size / 2;
    final dist = (p - Offset(c, c)).distance;
    // A generous band either side: the stroke itself is now too fine to aim at.
    final low = _innerRadius - innerStroke / 2 - 12;
    final high = _innerRadius + innerStroke / 2 + 12;
    return dist >= low && dist <= high;
  }

  /// The time band: proportional slices of the day, in the progress tone.
  _RingData _outer(GreyscaleTokens tokens) {
    final fill = tokens.ringFillInner;
    final track = tokens.ringTrack;

    // Tasks with time, keeping their original index for selection.
    final entries = <MapEntry<int, double>>[];
    for (var i = 0; i < taskTodaySeconds.length; i++) {
      if (taskTodaySeconds[i] > 0) {
        entries.add(MapEntry(i, taskTodaySeconds[i]));
      }
    }

    if (entries.isEmpty) {
      // Nothing logged → a solid empty track, no slits.
      return _RingData([_Seg(1, track)], slits: false);
    }

    Color colourFor(int taskIndex) {
      if (selectedTaskIndex == null) return fill; // collective: all filled
      return taskIndex == selectedTaskIndex ? fill : track; // highlight one
    }

    if (entries.length == 1) {
      // Single task with time → full solid ring, no slit.
      return _RingData([_Seg(1, colourFor(entries.first.key))], slits: false);
    }

    return _RingData(
      [for (final e in entries) _Seg(e.value, colourFor(e.key))],
      slits: true,
    );
  }

  /// The habits band: one equal arc per habit, white where it is done.
  _RingData _inner(GreyscaleTokens tokens) {
    if (habitStates.isEmpty) {
      // No habits defined → a solid empty track, no slits.
      return _RingData([_Seg(1, tokens.ringTrack)], slits: false);
    }
    return _RingData(
      [
        for (final done in habitStates)
          _Seg(1, done ? tokens.ringFillOuter : tokens.ringTrack),
      ],
      slits: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
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
              painter: _SegmentedBandPainter(
                slit: _slit,
                bands: [
                  _RingBand(_outerRadius, outerStroke, _outer(tokens)),
                  _RingBand(_innerRadius, innerStroke, _inner(tokens)),
                ],
              ),
            ),
          ),
          // Circular fill sized to sit just inside the outer ring's inner edge.
          if (fill != null)
            SizedBox(
              width: _outerRadius * 2 - outerStroke,
              height: _outerRadius * 2 - outerStroke,
              child: ClipOval(child: fill),
            ),
          ?center,
        ],
      ),
    );
  }
}

/// The habits band on its own — the same ring the dials carry inside them, at
/// whatever size a header needs.
///
/// One equal arc per habit, white where it is done, track where it is not, and
/// the same thin stroke. It reads the same state as the dial's inner band, so
/// ticking a habit fills a segment in both places at once.
class HabitsRing extends StatelessWidget {
  const HabitsRing({super.key, required this.states, this.size = 44});

  /// One entry per defined habit, true when it is done.
  final List<bool> states;

  final double size;

  /// The thin weight at this diameter.
  double get stroke => thinRingStroke(size);

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final radius = (size - stroke) / 2;
    final data = states.isEmpty
        ? _RingData([_Seg(1, tokens.ringTrack)], slits: false)
        : _RingData(
            [
              for (final done in states)
                _Seg(1, done ? tokens.ringFillOuter : tokens.ringTrack),
            ],
            slits: true,
          );

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size.square(size),
        // The slit scales with the ring, as it does on the dials.
        painter: _SegmentedBandPainter(
          slit: size * (3.5 / 57),
          bands: [_RingBand(radius, stroke, data)],
        ),
      ),
    );
  }
}

/// One ring segment: a relative [weight] (arc share) and its [color].
class _Seg {
  const _Seg(this.weight, this.color);
  final double weight;
  final Color color;
}

/// One ring's segments, and whether slits are cut between them.
class _RingData {
  const _RingData(this.segments, {required this.slits});
  final List<_Seg> segments;
  final bool slits;
}

/// One concentric band: where it sits, how thick it is, and what it holds.
class _RingBand {
  const _RingBand(this.radius, this.stroke, this.data);
  final double radius;
  final double stroke;
  final _RingData data;
}

/// Paints any number of concentric segmented bands, each at its own stroke.
///
/// Shared by the dual dial and the standalone habits ring — a segment drawn by
/// two painters would drift apart.
class _SegmentedBandPainter extends CustomPainter {
  _SegmentedBandPainter({required this.slit, required this.bands});

  /// Gap between segments, in logical pixels at the ring's radius.
  final double slit;
  final List<_RingBand> bands;

  static const double _startAngle = -math.pi / 2; // 12 o'clock

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (final band in bands) {
      _paintBand(canvas, center, band);
    }
  }

  void _paintBand(Canvas canvas, Offset center, _RingBand band) {
    final segments = band.data.segments;
    if (segments.isEmpty || band.radius <= 0) return;
    final total = segments.fold<double>(0, (s, seg) => s + seg.weight);
    if (total <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: band.radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt // clean square slit edges
      ..strokeWidth = band.stroke;

    // A slit is a fixed gap in pixels; convert to an angle at this radius.
    final slitAngle = (band.data.slits && segments.length > 1)
        ? (slit / band.radius)
        : 0.0;
    final available = (2 * math.pi) - (slitAngle * segments.length);
    var start = _startAngle + slitAngle / 2;

    for (final seg in segments) {
      final sweep = (seg.weight / total) * available;
      paint.color = seg.color;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep + slitAngle;
    }
  }

  @override
  bool shouldRepaint(_SegmentedBandPainter old) {
    if (old.slit != slit || old.bands.length != bands.length) return true;
    for (var i = 0; i < bands.length; i++) {
      final a = old.bands[i];
      final b = bands[i];
      if (a.radius != b.radius || a.stroke != b.stroke) return true;
      if (a.data.slits != b.data.slits ||
          a.data.segments.length != b.data.segments.length) {
        return true;
      }
      for (var j = 0; j < a.data.segments.length; j++) {
        if (a.data.segments[j].weight != b.data.segments[j].weight ||
            a.data.segments[j].color != b.data.segments[j].color) {
          return true;
        }
      }
    }
    return false;
  }
}

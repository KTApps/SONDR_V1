import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The home dial's data-driven dual ring (segmented, pure greyscale).
///
/// Distinct from [RingDial] (used for completed-milestone rings on the feed,
/// celebration, and day-detail): this one renders today's live state as
/// discrete segments cut by slits, per the Figma.
///
///  * **Outer ring** = today's time split across tasks. One segment per task
///    with time today, arc length proportional to that time. One task → a full
///    solid ring (no slit); no tasks → a full empty ring (no slit). When a
///    specific task is selected, its segment is filled and the rest dimmed.
///  * **Inner ring** = today's habits. One segment per *defined* habit (slits
///    always present), filled if completed today, empty if not.
///
/// Dimensions follow the Figma proportionally (outer 290 / inner 220 / stroke
/// 20 / slit 5, scaled to [size]).
class SegmentedDial extends StatelessWidget {
  const SegmentedDial({
    super.key,
    required this.taskTodaySeconds,
    this.selectedTaskIndex,
    required this.habitStates,
    this.size = 260,
    this.center,
    this.onInnerRingTap,
  });

  /// Seconds logged today per task, in stable task order (zeros included).
  final List<double> taskTodaySeconds;

  /// Index into [taskTodaySeconds] of the selected task, or null for the
  /// collective ("all tasks") view.
  final int? selectedTaskIndex;

  /// Completion state of each *defined* habit today (one entry per habit).
  final List<bool> habitStates;

  /// Overall diameter of the dial box.
  final double size;

  /// Centre content (the screen owns the today/month figure and its gestures).
  final Widget? center;

  /// Tapped on the inner (habit) ring band.
  final VoidCallback? onInnerRingTap;

  // Exact Figma values: recorded/filled and empty/no-data.
  static const Color _filled = Color(0xFF777777);
  static const Color _empty = Color(0xFF232323);

  // Figma geometry. 290 / 220 are the ring path (centreline) diameters and the
  // stroke (22) straddles them, so the outer ring's true extent is 312 (290+22).
  // Scaling by size/312 fits that extent to the box and preserves the concentric
  // gap: centreline radii 145 vs 110 → a 35px-per-side inset, matching the
  // Figma. The 35px centreline gap is independent of stroke weight.
  double get _stroke => size * 22 / 312;
  double get _outerRadius => size * 145 / 312; // centreline; outer edge = size/2
  double get _innerRadius => size * 110 / 312;
  double get _slit => size * 5 / 312;

  bool _hitsInnerRing(Offset p) {
    final c = size / 2;
    final dist = (p - Offset(c, c)).distance;
    final low = _innerRadius - _stroke / 2 - 12;
    final high = _innerRadius + _stroke / 2 + 12;
    return dist >= low && dist <= high;
  }

  _RingData _outer() {
    // Tasks with time today, keeping their original index for selection.
    final entries = <MapEntry<int, double>>[];
    for (var i = 0; i < taskTodaySeconds.length; i++) {
      if (taskTodaySeconds[i] > 0) entries.add(MapEntry(i, taskTodaySeconds[i]));
    }

    if (entries.isEmpty) {
      // No data today → solid empty ring, no slits.
      return const _RingData([_Seg(1, _empty)], slits: false);
    }

    Color colourFor(int taskIndex) {
      if (selectedTaskIndex == null) return _filled; // collective: all filled
      return taskIndex == selectedTaskIndex ? _filled : _empty; // highlight one
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

  _RingData _inner() {
    if (habitStates.isEmpty) {
      // No habits defined → solid empty ring, no slits.
      return const _RingData([_Seg(1, _empty)], slits: false);
    }
    // One equal segment per defined habit, slits always present.
    return _RingData(
      [for (final done in habitStates) _Seg(1, done ? _filled : _empty)],
      slits: true,
    );
  }

  @override
  Widget build(BuildContext context) {
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
              painter: _SegmentedDialPainter(
                outerRadius: _outerRadius,
                innerRadius: _innerRadius,
                stroke: _stroke,
                slit: _slit,
                outer: _outer(),
                inner: _inner(),
              ),
            ),
          ),
          ?center,
        ],
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

/// A ring's segments plus whether slits separate them.
class _RingData {
  const _RingData(this.segments, {required this.slits});
  final List<_Seg> segments;
  final bool slits;
}

class _SegmentedDialPainter extends CustomPainter {
  _SegmentedDialPainter({
    required this.outerRadius,
    required this.innerRadius,
    required this.stroke,
    required this.slit,
    required this.outer,
    required this.inner,
  });

  final double outerRadius;
  final double innerRadius;
  final double stroke;
  final double slit;
  final _RingData outer;
  final _RingData inner;

  static const double _startAngle = -math.pi / 2; // 12 o'clock

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    _paintRing(canvas, center, outerRadius, outer);
    _paintRing(canvas, center, innerRadius, inner);
  }

  void _paintRing(Canvas canvas, Offset center, double radius, _RingData data) {
    final segments = data.segments;
    if (segments.isEmpty || radius <= 0) return;
    final total = segments.fold<double>(0, (s, seg) => s + seg.weight);
    if (total <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt // clean square slit edges
      ..strokeWidth = stroke;

    // A slit is a 5px gap; convert to an angle at this radius.
    final slitAngle =
        (data.slits && segments.length > 1) ? (slit / radius) : 0.0;
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
  bool shouldRepaint(_SegmentedDialPainter old) {
    return old.outerRadius != outerRadius ||
        old.innerRadius != innerRadius ||
        old.stroke != stroke ||
        old.slit != slit ||
        !_sameRing(old.outer, outer) ||
        !_sameRing(old.inner, inner);
  }

  bool _sameRing(_RingData a, _RingData b) {
    if (a.slits != b.slits || a.segments.length != b.segments.length) {
      return false;
    }
    for (var i = 0; i < a.segments.length; i++) {
      if (a.segments[i].weight != b.segments[i].weight ||
          a.segments[i].color != b.segments[i].color) {
        return false;
      }
    }
    return true;
  }
}

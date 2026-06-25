import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A single-value greyscale progress ring (no segments, no slits): the arc fills
/// #777777 in proportion to [progress] (0..1) over a #232323 remainder, starting
/// at 12 o'clock. Used where one value is shown — a task's progress toward its
/// milestone (profile), and the single completed-milestone ring on feed posts.
///
/// The stroke scales with [size] using the same proportional approach as the
/// mini segmented circles (7/57 of the box), so it sits in the same greyscale
/// ring family as the main dial. Pass [center] for the centre figure.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.progress,
    this.size = 72,
    this.center,
  });

  /// 0..1 — the filled fraction of the ring.
  final double progress;

  /// Overall diameter of the ring box.
  final double size;

  /// Centre content (e.g. the "Nh" figure).
  final Widget? center;

  static const Color _filled = Color(0xFF777777);
  static const Color _empty = Color(0xFF232323);

  double get _stroke => size * 7 / 57;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _ProgressRingPainter(
              progress: progress.clamp(0.0, 1.0),
              stroke: _stroke,
              filled: _filled,
              empty: _empty,
            ),
          ),
          ?center,
        ],
      ),
    );
  }
}

class _ProgressRingPainter extends CustomPainter {
  _ProgressRingPainter({
    required this.progress,
    required this.stroke,
    required this.filled,
    required this.empty,
  });

  final double progress;
  final double stroke;
  final Color filled;
  final Color empty;

  static const double _startAngle = -math.pi / 2; // 12 o'clock

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2 - stroke / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = stroke;

    // Remainder: the full ring in the empty tone underneath.
    paint.color = empty;
    canvas.drawArc(rect, _startAngle, 2 * math.pi, false, paint);

    // Filled arc: the progress portion on top.
    if (progress > 0) {
      paint.color = filled;
      canvas.drawArc(rect, _startAngle, progress * 2 * math.pi, false, paint);
    }
  }

  @override
  bool shouldRepaint(_ProgressRingPainter old) {
    return old.progress != progress ||
        old.stroke != stroke ||
        old.filled != filled ||
        old.empty != empty;
  }
}

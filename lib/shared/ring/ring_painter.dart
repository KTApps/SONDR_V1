import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Base for one concentric ring on a dial. Rings are drawn outermost-first and
/// stepped inward by the painter.
@immutable
sealed class RingLayer {
  const RingLayer({required this.thickness});

  /// Stroke width of this ring.
  final double thickness;
}

/// A single proportional slice of a [SegmentRingLayer].
@immutable
class RingSegment {
  const RingSegment({required this.value, required this.color});

  /// Relative magnitude (e.g. seconds logged on a task today). Slices are sized
  /// by each value's share of the total.
  final double value;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is RingSegment && other.value == value && other.color == color;

  @override
  int get hashCode => Object.hash(value, color);
}

/// A pie/donut ring: the full circle split into proportional [segments]. Used
/// for the outer ring, which shows how a day's time is divided across tasks.
class SegmentRingLayer extends RingLayer {
  const SegmentRingLayer({
    required super.thickness,
    required this.segments,
    required this.track,
  });

  final List<RingSegment> segments;

  /// Shown when nothing has been logged (every segment zero).
  final Color track;

  @override
  bool operator ==(Object other) =>
      other is SegmentRingLayer &&
      other.thickness == thickness &&
      other.track == track &&
      listEquals(other.segments, segments);

  @override
  int get hashCode => Object.hash(thickness, track, Object.hashAll(segments));
}

/// A track + single progress arc. Used for the inner habit ring
/// (completed ÷ total).
class ProgressRingLayer extends RingLayer {
  const ProgressRingLayer({
    required super.thickness,
    required this.progress,
    required this.track,
    required this.fill,
  });

  final double progress;
  final Color track;
  final Color fill;

  @override
  bool operator ==(Object other) =>
      other is ProgressRingLayer &&
      other.thickness == thickness &&
      other.progress == progress &&
      other.track == track &&
      other.fill == fill;

  @override
  int get hashCode => Object.hash(thickness, progress, track, fill);
}

/// Paints the dual ring. Outer ring is typically a [SegmentRingLayer] (the
/// task split), inner a [ProgressRingLayer] (habits). The double-stroke
/// contrast-halo variant for photo backdrops is kept built-in via [onPhoto] so
/// the same component renders legibly over any image in phase 2.
class RingPainter extends CustomPainter {
  RingPainter({
    required this.layers,
    this.onPhoto = false,
  });

  final List<RingLayer> layers;
  final bool onPhoto;

  // Start at 12 o'clock; sweep clockwise (positive — canvas y points down).
  static const double _startAngle = -math.pi / 2;
  // Angular gap between adjacent pie segments.
  static const double _segmentGap = 0.05;

  @override
  void paint(Canvas canvas, Size size) {
    if (layers.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxThickness = layers.map((l) => l.thickness).reduce(math.max);
    final haloPad = onPhoto ? maxThickness * 0.18 : 0.0;
    var radius =
        (math.min(size.width, size.height) / 2) - (maxThickness / 2) - haloPad;
    final gap = size.shortestSide * 0.035;

    for (var i = 0; i < layers.length; i++) {
      final layer = layers[i];
      switch (layer) {
        case SegmentRingLayer():
          _paintSegments(canvas, center, radius, layer);
        case ProgressRingLayer():
          _paintProgress(canvas, center, radius, layer);
      }
      if (i + 1 < layers.length) {
        radius -=
            (layer.thickness / 2) + gap + (layers[i + 1].thickness / 2);
      }
    }
  }

  void _paintSegments(
    Canvas canvas,
    Offset center,
    double radius,
    SegmentRingLayer layer,
  ) {
    final rect = Rect.fromCircle(center: center, radius: radius);

    if (onPhoto) {
      final trackHalo = Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = layer.thickness * 1.18;
      canvas.drawArc(rect, _startAngle, 2 * math.pi, false, trackHalo);
    }

    // Track underneath, so a partially-filled day still reads as a full ring.
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = layer.track
      ..strokeWidth = layer.thickness;
    canvas.drawArc(rect, _startAngle, 2 * math.pi, false, trackPaint);

    final segs = layer.segments.where((s) => s.value > 0).toList();
    final total = segs.fold<double>(0, (sum, s) => sum + s.value);
    if (total <= 0) return;

    final count = segs.length;
    final gap = count > 1 ? _segmentGap : 0.0;
    final available = (2 * math.pi) - (gap * count);
    var start = _startAngle + (gap / 2);

    for (final seg in segs) {
      final sweep = (seg.value / total) * available;
      if (onPhoto) {
        final halo = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..color = Colors.black.withValues(alpha: 0.45)
          ..strokeWidth = layer.thickness * 1.3;
        canvas.drawArc(rect, start, sweep, false, halo);
      }
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = count > 1 ? StrokeCap.round : StrokeCap.butt
        ..color = seg.color
        ..strokeWidth = layer.thickness;
      canvas.drawArc(rect, start, sweep, false, paint);
      start += sweep + gap;
    }
  }

  void _paintProgress(
    Canvas canvas,
    Offset center,
    double radius,
    ProgressRingLayer layer,
  ) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = layer.progress.clamp(0.0, 1.0) * 2 * math.pi;

    if (onPhoto) {
      final trackHalo = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.18)
        ..strokeWidth = layer.thickness * 1.18;
      canvas.drawArc(rect, _startAngle, 2 * math.pi, false, trackHalo);
      if (sweep > 0) {
        final fillHalo = Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..color = Colors.black.withValues(alpha: 0.45)
          ..strokeWidth = layer.thickness * 1.32;
        canvas.drawArc(rect, _startAngle, sweep, false, fillHalo);
      }
    }

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = layer.track
      ..strokeWidth = layer.thickness;
    canvas.drawArc(rect, _startAngle, 2 * math.pi, false, trackPaint);

    if (sweep > 0) {
      final fillPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..color = layer.fill
        ..strokeWidth = layer.thickness;
      canvas.drawArc(rect, _startAngle, sweep, false, fillPaint);
    }
  }

  @override
  bool shouldRepaint(RingPainter old) {
    return old.onPhoto != onPhoto || !listEquals(old.layers, layers);
  }
}

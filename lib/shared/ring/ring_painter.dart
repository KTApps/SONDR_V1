import 'dart:math' as math;

import 'package:flutter/material.dart';

/// One concentric ring's drawing recipe: a full-circle [track] with a
/// progress [fill] arc on top. Both rings on a dial share this shape and differ
/// only by brightness and radius — never by hue.
@immutable
class RingLayer {
  const RingLayer({
    required this.progress,
    required this.thickness,
    required this.track,
    required this.fill,
  });

  /// 0..1 portion filled, drawn clockwise from 12 o'clock.
  final double progress;

  /// Stroke width of this ring.
  final double thickness;

  /// Empty-portion colour (the muted mid-grey from the ladder).
  final Color track;

  /// Progress colour (outer = brightest, inner = one step dimmer).
  final Color fill;
}

/// Paints the dual ring. Two responsibilities live here so the rest of the app
/// never re-implements ring geometry:
///
///  * The plain greyscale dial used on solid surfaces (home, history, profile).
///  * The **double-stroke** variant for photo backdrops — under each fill arc
///    sits a slightly wider semi-transparent dark stroke, and under each track
///    a faint light stroke, so every ring carries its own contrast halo and
///    never relies on the photo behind it cooperating (the film-subtitle
///    outline trick). Enable with [onPhoto].
class RingPainter extends CustomPainter {
  RingPainter({
    required this.layers,
    this.onPhoto = false,
  });

  /// Rings drawn outermost-first. Typically [outerTask, innerHabit].
  final List<RingLayer> layers;

  /// When true, draws the dark/light contrast halos described above.
  final bool onPhoto;

  // Start at 12 o'clock; sweep clockwise (positive, since canvas y points down).
  static const double _startAngle = -math.pi / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Keep the outermost stroke (plus any halo) inside the bounds.
    final maxThickness = layers.isEmpty
        ? 0.0
        : layers.map((l) => l.thickness).reduce(math.max);
    final haloPad = onPhoto ? maxThickness * 0.18 : 0.0;
    var radius = (math.min(size.width, size.height) / 2) -
        (maxThickness / 2) -
        haloPad;

    final gap = size.shortestSide * 0.035;

    for (var i = 0; i < layers.length; i++) {
      final layer = layers[i];
      _paintLayer(canvas, center, radius, layer);
      // Step inward: clear this ring's inner edge, the gap, then the next
      // ring's outer edge.
      if (i + 1 < layers.length) {
        radius -= (layer.thickness / 2) + gap + (layers[i + 1].thickness / 2);
      }
    }
  }

  void _paintLayer(
    Canvas canvas,
    Offset center,
    double radius,
    RingLayer layer,
  ) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = layer.progress.clamp(0.0, 1.0) * 2 * math.pi;

    // --- Halos (photo case only): drawn first so the real strokes sit atop. ---
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

    // --- Track: full circle of the empty tone. ---
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..color = layer.track
      ..strokeWidth = layer.thickness;
    canvas.drawArc(rect, _startAngle, 2 * math.pi, false, trackPaint);

    // --- Fill: the progress arc, rounded cap, clockwise from the top. ---
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
    if (old.onPhoto != onPhoto || old.layers.length != layers.length) {
      return true;
    }
    for (var i = 0; i < layers.length; i++) {
      final a = layers[i];
      final b = old.layers[i];
      if (a.progress != b.progress ||
          a.thickness != b.thickness ||
          a.track != b.track ||
          a.fill != b.fill) {
        return true;
      }
    }
    return false;
  }
}

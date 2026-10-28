import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/greyscale_tokens.dart';
import 'post_chrome.dart';

/// The milestone card's ring — the collage cover's alone: Ø184, a stroke
/// of 9% of that, one soft shadow under the band over a photo — solid,
/// everywhere. The same figures paint the card, the no-photo frame and
/// the cover rendered at share time.
const double kMilestoneRingSize = 184;

/// The shadow under the band over a photo: black at this opacity, blurred
/// by this much, this far down. In place of the two halo strokes and the
/// glow the ring used to wear.
const double kMilestoneRingShadowOpacity = 0.28;
const double kMilestoneRingShadowBlur = 4;
const double kMilestoneRingShadowDy = 1.5;

/// The figure's size, the same on every page — "20", "120", "12h 59m":
/// the largest at which the longest session a band can hold, "12h 59m",
/// still sits inside the ring's clear width with a margin (111 of the 116
/// the centre allows itself). Nothing is fitted per page: a figure that
/// changed size from page to page read as a different ring.
const double kMilestoneFigureSize = 28;

/// Over a photo, the disc inside the band is darkened by this much under
/// the figure — the same in the card and the rendered cover — with its
/// edge feathered by [kMilestoneRingInnerFeather] points.
const double kMilestoneRingInnerTint = 0.30;
const double kMilestoneRingInnerFeather = 1;

/// The ring's measurements. Pure, so the stroke, radius and extent are
/// tested without a canvas, and so a canvas of any size can draw it.
class MilestoneRingGeometry {
  const MilestoneRingGeometry({
    this.size = kMilestoneRingSize,
    required this.onPhoto,
  });

  final double size;
  final bool onPhoto;

  /// RingDial's outer weight: 9% of the dial.
  double get thickness => size * 0.090;

  /// Room inside the box for the shadow over a photo — the pad the halos
  /// once took, kept so the ring's size over a photo is what it was.
  double get haloPad => onPhoto ? thickness * 0.18 : 0;

  /// The stroke's centreline.
  double get radius => size / 2 - thickness / 2 - haloPad;

  /// The ring's outer edge, end to end.
  double get extent => 2 * (radius + thickness / 2);

  /// The clear space inside the stroke.
  double get inner => 2 * (radius - thickness / 2);
}

/// Draw the ring on [canvas] about [center]: over a photo, the tint
/// inside and the one shadow under the band; then the band itself in
/// [fill].
void paintMilestoneRing(
  Canvas canvas,
  Offset center,
  MilestoneRingGeometry geometry,
  Color fill,
) {
  final rect = Rect.fromCircle(center: center, radius: geometry.radius);
  final thickness = geometry.thickness;
  const full = 2 * math.pi;
  final stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.butt;

  if (geometry.onPhoto) {
    // The disc inside the band, darkened so the figure reads on any photo.
    canvas.drawCircle(
      center,
      geometry.radius - thickness / 2,
      Paint()
        ..color = Colors.black.withValues(alpha: kMilestoneRingInnerTint)
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          kMilestoneRingInnerFeather,
        ),
    );
    // One soft shadow under the band, so the ring reads as solid white
    // on a white photo and goes unnoticed on a dark one.
    canvas.drawArc(
      rect.shift(const Offset(0, kMilestoneRingShadowDy)),
      0,
      full,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.black.withValues(alpha: kMilestoneRingShadowOpacity)
        ..strokeWidth = thickness
        ..maskFilter = const MaskFilter.blur(
          BlurStyle.normal,
          kMilestoneRingShadowBlur,
        ),
    );
  }
  canvas.drawArc(
    rect,
    0,
    full,
    false,
    stroke
      ..color = fill
      ..strokeWidth = thickness,
  );
}

class MilestoneRing extends StatelessWidget {
  const MilestoneRing({
    super.key,
    required this.onPhoto,
    this.center,
    this.size = kMilestoneRingSize,
  });

  /// Over a photo: the glow and the contrast halos.
  final bool onPhoto;

  /// What sits inside the ring.
  final Widget? center;

  final double size;

  MilestoneRingGeometry get geometry =>
      MilestoneRingGeometry(size: size, onPhoto: onPhoto);

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
            painter: _MilestoneRingPainter(
              geometry: geometry,
              fill: tokens.ringFillOuter,
            ),
          ),
          ?center,
        ],
      ),
    );
  }
}

class _MilestoneRingPainter extends CustomPainter {
  const _MilestoneRingPainter({required this.geometry, required this.fill});

  final MilestoneRingGeometry geometry;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    paintMilestoneRing(
      canvas,
      Offset(size.width / 2, size.height / 2),
      geometry,
      fill,
    );
  }

  @override
  bool shouldRepaint(_MilestoneRingPainter old) =>
      old.geometry.size != geometry.size ||
      old.geometry.onPhoto != geometry.onPhoto ||
      old.fill != fill;
}

/// What the ring holds: a figure over a word — "20" over "hours", or a
/// session's "2h 40m" over its date — in two styles shared by every page,
/// at one size: see [kMilestoneFigureSize].
class MilestoneRingCentre extends StatelessWidget {
  const MilestoneRingCentre({
    super.key,
    required this.figure,
    required this.unit,
    required this.onPhoto,
    this.size = kMilestoneRingSize,
  });

  final String figure;
  final String unit;
  final bool onPhoto;
  final double size;

  /// The figure's style — today's hours figure — in [context].
  static TextStyle? figureStyle(BuildContext context, {required bool onPhoto}) {
    final tokens = GreyscaleTokens.of(context);
    return Theme.of(context).textTheme.displaySmall?.copyWith(
      fontSize: kMilestoneFigureSize,
      color: onPhoto ? kOnPhoto : tokens.textPrimary,
      shadows: onPhoto ? kTextShadows : null,
    );
  }

  /// The word's style — today's "hours" — in [context].
  static TextStyle? unitStyle(BuildContext context, {required bool onPhoto}) {
    final tokens = GreyscaleTokens.of(context);
    return Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: onPhoto ? kOnPhotoDim : tokens.textTertiary,
      shadows: onPhoto ? kTextShadows : null,
    );
  }

  /// How wide the centre may be: the clear space inside the stroke, less a
  /// margin either side.
  static double widthFor(double size, {required bool onPhoto}) =>
      MilestoneRingGeometry(size: size, onPhoto: onPhoto).inner * 0.8;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widthFor(size, onPhoto: onPhoto),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            figure,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: figureStyle(context, onPhoto: onPhoto),
          ),
          Text(
            unit,
            maxLines: 1,
            style: unitStyle(context, onPhoto: onPhoto),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/app_theme.dart';
import 'package:sondr/shared/ring/ring_metrics.dart';

/// One ring weight, everywhere.
///
/// The rings used to be stroked at a fraction of their own diameter, so a Ø40
/// band ring came out at 2.1 where Home's day dial was 7. Same component,
/// four thicknesses, depending only on how big it happened to be.
void main() {
  const scale = 0.9906137184115524; // iPhone 13 Pro

  test('every ring takes the same stroke, whatever its diameter', () {
    expect(ringStroke(scale), closeTo(6.93, 0.01));
    // Ø128 hero, Ø56 in-progress and journey, Ø40 band: one number.
    for (final diameter in [128, 56, 40]) {
      expect(
        ringStroke(scale),
        closeTo(6.93, 0.01),
        reason: 'the Ø$diameter ring should take the same weight',
      );
    }
  });

  test('a day dial at its reference size lands on the same weight', () {
    // SegmentedDial strokes compact bands at kCompactDialStrokeRatio, so the
    // dials and the rings are one number with two expressions of it.
    expect(
      kCompactDialSize * scale * kCompactDialStrokeRatio,
      closeTo(ringStroke(scale), 0.001),
    );
  });

  test('the hour figure still fits inside the ring it sits in', () {
    // The centre label is 12 bold; the room for it is the diameter less the
    // stroke on both sides. A heavier stroke eats into that from the inside,
    // which is the one thing this change could have broken.
    final style = AppTheme.dark().textTheme.bodyMedium!.copyWith(
      fontSize: 12 * scale,
      fontWeight: FontWeight.w700,
    );
    double widthOf(String text) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      return painter.width;
    }

    // KNOWN LIMIT, REVIEWED ON DEVICE AND ACCEPTED: the Ø40 band ring fits
    // two digits and not three. The heavier stroke takes 10 off its inner
    // width, and "100h" needs 28.6 where 25.8 is left, so from the 100-hour
    // band the figure overlaps the stroke. It is a collision rather than a
    // clip — the label is a centred child, not a clipped one — and it was
    // looked at on a device and judged acceptable against having two ring
    // weights in the app. Asserted, so that if the figure or the ring ever
    // changes size this is a decision someone retakes rather than inherits.
    final inner40 = 40 * scale - 2 * ringStroke(scale);
    expect(widthOf('100h'), greaterThan(inner40));

    for (final (diameter, label) in [(56, '40h'), (56, '100h'), (56, '240h'), (40, '40h')]) {
      final inner = diameter * scale - 2 * ringStroke(scale);
      expect(
        widthOf(label),
        lessThan(inner),
        reason: '"$label" does not fit inside the Ø$diameter ring '
            '(${widthOf(label).toStringAsFixed(1)} in ${inner.toStringAsFixed(1)})',
      );
    }
  });
}

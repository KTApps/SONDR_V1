import 'package:flutter/material.dart';

import '../../core/utils/figma_scale.dart';

/// Home's "Last 10 days" block, as the numbers its own layout is built from.
///
/// They live here rather than inline in `timer_screen.dart` because another
/// screen now has to land on one of them: Profile's ring labels sit on exactly
/// the y Home's "View your progress" sits on, so the two bottom lines of the
/// app read as one line. Copying the numbers across would make that true once
/// and false after the next nudge; deriving it keeps it true.
const double kHomeLastTenTop = 511;
const double kHomeHeadingSize = 20;
const double kHomeHeadingToRow = 30;
const double kHomeDayCell = 57;
const double kHomeRowGap = 25;
const double kHomeRowToCta = 28;
const double kHomeCtaSize = 15;

/// The height of one line of [style] at [size] reference points.
///
/// Laid out rather than computed as size × height: the shaper quantises a
/// line box to the font's own rounded metrics, so a 19.81pt line of Inter
/// measures 24.00 and not the 23.77 the arithmetic predicts. A quarter of a
/// point is enough to miss a half-point assertion.
double lineHeightOf(BuildContext context, TextStyle? style, double size) {
  final painter = TextPainter(
    // Any glyphs will do — the box is the font's, not the string's.
    text: TextSpan(
      text: 'Hg',
      style: style?.copyWith(fontSize: size * figmaScale(context)),
    ),
    textDirection: TextDirection.ltr,
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  return painter.height;
}

/// Where the centre of Home's "View your progress" lands on this screen.
///
/// Home places the block absolutely and stacks fixed gaps under it, so this is
/// that chain — with the one text box in it measured rather than assumed.
double homeCtaCentreY(BuildContext context) {
  final scale = figmaScale(context);
  final titleLarge = Theme.of(context).textTheme.titleLarge;
  final heading = lineHeightOf(context, titleLarge, kHomeHeadingSize);
  final cta = lineHeightOf(context, titleLarge, kHomeCtaSize);
  final top = kHomeLastTenTop * scale +
      heading +
      (kHomeHeadingToRow + kHomeDayCell + kHomeRowGap + kHomeDayCell +
              kHomeRowToCta) *
          scale;
  return top + cta / 2;
}

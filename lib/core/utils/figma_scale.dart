import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The Figma canvas the screens' positions and sizes were measured on.
const double kFigmaRefWidth = 393;
const double kFigmaRefHeight = 852;

/// How much to scale a Figma-measured value for the screen it is drawn on.
///
/// One uniform factor — the smaller of the width and height ratios — so a
/// layout keeps the design's exact proportions on any iPhone, and can neither
/// distort nor overlap on a screen shorter or narrower than the reference.
///
/// Exactly 1.0 on a 393x852 screen, which leaves the reference rendering
/// byte-for-byte as it was measured.
double figmaScale(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return math.min(size.width / kFigmaRefWidth, size.height / kFigmaRefHeight);
}

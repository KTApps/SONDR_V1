import 'package:flutter/material.dart';

/// Typography for Sondr. One typeface — Inter — bundled as a single variable
/// font, with weights kept to regular / medium / bold. Copy throughout the app
/// is sentence case (see the spec); that's an editorial rule, not enforced
/// here, but these styles are the only ones screens should reach for.
abstract final class AppTypography {
  static const String fontFamily = 'Inter';

  /// Builds the [TextTheme], colouring every style from the greyscale ladder so
  /// text never introduces hue. [primary] is the high-contrast tone,
  /// [secondary] the supporting tone.
  static TextTheme textTheme({
    required Color primary,
    required Color secondary,
  }) {
    TextStyle base(
      double size,
      FontWeight weight,
      Color color, {
      double height = 1.2,
      double letterSpacing = 0,
    }) {
      return TextStyle(
        fontFamily: fontFamily,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
    }

    return TextTheme(
      // Big effort figures (the centre of the ring, lifetime hours).
      displayLarge: base(56, FontWeight.w700, primary, height: 1.0, letterSpacing: -1.0),
      displayMedium: base(40, FontWeight.w700, primary, height: 1.05, letterSpacing: -0.5),
      // Screen + section titles.
      headlineMedium: base(28, FontWeight.w600, primary, letterSpacing: -0.3),
      titleLarge: base(22, FontWeight.w600, primary, letterSpacing: -0.2),
      titleMedium: base(17, FontWeight.w500, primary),
      // Body and labels.
      bodyLarge: base(16, FontWeight.w400, primary, height: 1.4),
      bodyMedium: base(14, FontWeight.w400, secondary, height: 1.4),
      labelLarge: base(15, FontWeight.w500, primary),
      labelMedium: base(13, FontWeight.w500, secondary, letterSpacing: 0.2),
      labelSmall: base(11, FontWeight.w500, secondary, letterSpacing: 0.4),
    );
  }
}

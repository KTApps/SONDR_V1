import 'package:flutter/material.dart';

import 'greyscale_tokens.dart';
import 'typography.dart';

/// Assembles [ThemeData] for both modes from the greyscale [GreyscaleTokens].
/// The light theme is the same ladder inverted — nothing here introduces hue.
abstract final class AppTheme {
  static ThemeData dark() => _build(Brightness.dark, GreyscaleTokens.dark);
  static ThemeData light() => _build(Brightness.light, GreyscaleTokens.light);

  static ThemeData _build(Brightness brightness, GreyscaleTokens tokens) {
    // A pure-greyscale scheme: seed everything off the fill/track tones so no
    // stray Material accent (the default indigo/teal) can leak in.
    final scheme = ColorScheme(
      brightness: brightness,
      primary: tokens.ringFillOuter,
      onPrimary: tokens.background,
      secondary: tokens.ringFillInner,
      onSecondary: tokens.background,
      surface: tokens.surface,
      onSurface: tokens.textPrimary,
      error: tokens.textPrimary,
      onError: tokens.background,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: tokens.background,
      canvasColor: tokens.background,
      fontFamily: AppTypography.fontFamily,
      textTheme: AppTypography.textTheme(
        primary: tokens.textPrimary,
        secondary: tokens.textSecondary,
      ),
      iconTheme: IconThemeData(color: tokens.textPrimary),
      extensions: <ThemeExtension<dynamic>>[tokens],
    );
  }
}

import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';

/// Assigns greyscale tones to the outer ring's task segments. Segments are told
/// apart by brightness only (never hue), staying clearly above the track tone
/// so the split reads on any background.
abstract final class RingPalette {
  /// Even brightness ramp for [count] segments — used in collective ("Task")
  /// mode where no single task is emphasised. Brightest first, stepping down
  /// toward the dimmer fill tone.
  static List<Color> ramp(
    GreyscaleTokens tokens,
    int count, {
    bool onPhoto = false,
  }) {
    final bright = onPhoto ? const Color(0xFFFFFFFF) : tokens.ringFillOuter;
    final dim = onPhoto ? const Color(0xFFB4B4B4) : tokens.ringFillInner;
    if (count <= 1) return [bright];
    return [
      for (var i = 0; i < count; i++)
        Color.lerp(bright, dim, i / (count - 1))!,
    ];
  }

  /// One segment emphasised (the selected task): that segment is the brightest
  /// tone, the rest drop to a single dim grey so the selection pops while the
  /// whole day's split stays visible.
  static List<Color> highlighted(
    GreyscaleTokens tokens,
    int count,
    int index, {
    bool onPhoto = false,
  }) {
    final hi = onPhoto ? const Color(0xFFFFFFFF) : tokens.ringFillOuter;
    final rest = onPhoto
        ? const Color(0x73FFFFFF) // ~45% white
        : Color.lerp(tokens.ringFillInner, tokens.ringTrack, 0.3)!;
    return [
      for (var i = 0; i < count; i++) i == index ? hi : rest,
    ];
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sondr/core/theme/greyscale_tokens.dart';
import 'package:sondr/features/profile/profile_metrics.dart';
import 'package:sondr/shared/ring/ring_palette.dart';

/// Every colour the app draws comes from one file.
///
/// These pin the VALUES, not the names: the point of moving a literal into
/// the tokens is that nothing on screen changes, so each one is checked
/// against the hex it replaced.
void main() {
  group('the tones that are not on the ladder', () {
    test('the hairline is the one it always was', () {
      expect(kHairline, const Color(0xFF242424));
      // The Profile's own name for it is the same colour, not a second one.
      expect(kProfileHairline, kHairline);
    });

    test("Home's dial keeps its Figma values", () {
      expect(kDialFilled, const Color(0xFF777777));
      expect(kDialEmpty, const Color(0xFF232323));
    });

    test('the ring over a photo keeps its tones', () {
      expect(kOnPhoto, const Color(0xFFFFFFFF));
      expect(kOnPhotoRingFill, const Color(0xFFE6E6E6));
      expect(kOnPhotoRingDim, const Color(0xFFB4B4B4));
    });

    test('and they are far enough apart to read as a ring', () {
      // The reason these are fixed: a dial whose filled and empty tones
      // drift together stops being legible.
      expect(kDialFilled.computeLuminance(),
          greaterThan(kDialEmpty.computeLuminance() + 0.1));
      expect(kOnPhoto.computeLuminance(),
          greaterThan(kOnPhotoRingDim.computeLuminance() + 0.1));
    });
  });

  group('the ladder itself is unchanged', () {
    test('dark', () {
      const t = GreyscaleTokens.dark;
      expect(t.background, const Color(0xFF0A0A0A));
      expect(t.surface, const Color(0xFF161616));
      expect(t.ringTrack, const Color(0xFF3A3A3A));
      expect(t.ringFillOuter, const Color(0xFFFAFAFA));
      expect(t.ringFillInner, const Color(0xFFADADAD));
      expect(t.textPrimary, const Color(0xFFFAFAFA));
      expect(t.textSecondary, const Color(0xFFB0B0B0));
      expect(t.textTertiary, const Color(0xFF6E6E6E));
    });

    test('light', () {
      const t = GreyscaleTokens.light;
      expect(t.background, const Color(0xFFFAFAFA));
      expect(t.surface, const Color(0xFFFFFFFF));
      expect(t.ringTrack, const Color(0xFFC9C9C9));
      expect(t.ringFillOuter, const Color(0xFF0A0A0A));
      expect(t.ringFillInner, const Color(0xFF5A5A5A));
      expect(t.textPrimary, const Color(0xFF0A0A0A));
      expect(t.textSecondary, const Color(0xFF4A4A4A));
      expect(t.textTertiary, const Color(0xFF8A8A8A));
    });
  });

  group('what the ring actually paints', () {
    test('over a photo, the ramp runs from white to the dim tone', () {
      final ramp = RingPalette.ramp(GreyscaleTokens.dark, 3, onPhoto: true);
      expect(ramp.first, kOnPhoto);
      expect(ramp.last, kOnPhotoRingDim);
    });

    test('off a photo, it runs down the ladder instead', () {
      const tokens = GreyscaleTokens.dark;
      final ramp = RingPalette.ramp(tokens, 3);
      expect(ramp.first, tokens.ringFillOuter);
      expect(ramp.last, tokens.ringFillInner);
    });
  });
}

import 'package:flutter/material.dart';

/// Sondr is pure greyscale. There is no accent colour anywhere in the app —
/// all contrast comes from brightness, never hue. Legibility depends on keeping
/// the three core tones (surface, ring track, ring fill) far apart on the
/// brightness ladder. If track and fill drift toward each other the ring goes
/// mushy, so these are fixed design tokens and must never be tuned closer.
///
/// Exposed as a [ThemeExtension] so any widget can read the exact tone it needs
/// from `Theme.of(context).extension<GreyscaleTokens>()` (or the [of] helper).
/// Tones for text and chrome drawn ON TOP of a photo.
///
/// A photo is not part of the brightness ladder — it can be any luminance —
/// so content over one cannot use the surface tokens and stay legible. These
/// are the only literal whites in the app, and they exist for that reason;
/// everywhere else, read the tokens.
const Color kOnPhoto = Color(0xFFFFFFFF);

/// Supporting text over a photo.
const Color kOnPhotoDim = Color(0xB3FFFFFF);

/// A translucent chip or avatar backing over a photo.
const Color kOnPhotoFill = Color(0x3DFFFFFF);

/// Avatar diameters. One scale, three contexts: the Friends list, a feed
/// post's author row, and a comment. Circular everywhere.
const double kAvatarList = 36;
const double kAvatarPost = 32;
const double kAvatarComment = 28;

@immutable
class GreyscaleTokens extends ThemeExtension<GreyscaleTokens> {
  const GreyscaleTokens({
    required this.background,
    required this.surface,
    required this.ringTrack,
    required this.ringFillOuter,
    required this.ringFillInner,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
  });

  /// The app backdrop — the darkest (dark mode) or lightest (light mode) tone.
  final Color background;

  /// Card / panel surface. One step in from [background] so cards read as
  /// raised without relying on shadow or colour.
  final Color surface;

  /// The empty portion of a ring. A muted mid-grey, deliberately parked in the
  /// middle of the ladder so it stays distinct from both fills.
  final Color ringTrack;

  /// The outer (task) ring fill — the BRIGHTEST tone. Near-white in dark mode,
  /// near-black in light mode.
  final Color ringFillOuter;

  /// The inner (habit) ring fill — exactly ONE step dimmer than
  /// [ringFillOuter]. The two rings are told apart by brightness, never colour.
  final Color ringFillInner;

  /// Highest-contrast text (figures, titles).
  final Color textPrimary;

  /// Supporting text (labels, captions).
  final Color textSecondary;

  /// De-emphasised text (hints, units, metadata).
  final Color textTertiary;

  /// Dark mode: near-black surfaces, near-white fills.
  static const GreyscaleTokens dark = GreyscaleTokens(
    background: Color(0xFF0A0A0A),
    surface: Color(0xFF161616),
    ringTrack: Color(0xFF3A3A3A),
    ringFillOuter: Color(0xFFFAFAFA),
    ringFillInner: Color(0xFFADADAD),
    textPrimary: Color(0xFFFAFAFA),
    textSecondary: Color(0xFFB0B0B0),
    textTertiary: Color(0xFF6E6E6E),
  );

  /// Light mode: the same ladder inverted — near-white surfaces, near-black
  /// fills, dark arc on a mid-grey track.
  static const GreyscaleTokens light = GreyscaleTokens(
    background: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    ringTrack: Color(0xFFC9C9C9),
    ringFillOuter: Color(0xFF0A0A0A),
    ringFillInner: Color(0xFF5A5A5A),
    textPrimary: Color(0xFF0A0A0A),
    textSecondary: Color(0xFF4A4A4A),
    textTertiary: Color(0xFF8A8A8A),
  );

  /// Convenience accessor. Falls back to [dark] if the extension is somehow
  /// absent so callers never have to null-check the hero component's colours.
  static GreyscaleTokens of(BuildContext context) {
    return Theme.of(context).extension<GreyscaleTokens>() ?? dark;
  }

  @override
  GreyscaleTokens copyWith({
    Color? background,
    Color? surface,
    Color? ringTrack,
    Color? ringFillOuter,
    Color? ringFillInner,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
  }) {
    return GreyscaleTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      ringTrack: ringTrack ?? this.ringTrack,
      ringFillOuter: ringFillOuter ?? this.ringFillOuter,
      ringFillInner: ringFillInner ?? this.ringFillInner,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
    );
  }

  @override
  GreyscaleTokens lerp(ThemeExtension<GreyscaleTokens>? other, double t) {
    if (other is! GreyscaleTokens) return this;
    return GreyscaleTokens(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      ringTrack: Color.lerp(ringTrack, other.ringTrack, t)!,
      ringFillOuter: Color.lerp(ringFillOuter, other.ringFillOuter, t)!,
      ringFillInner: Color.lerp(ringFillInner, other.ringFillInner, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
    );
  }
}

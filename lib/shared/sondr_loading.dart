import 'package:flutter/material.dart';

import '../core/theme/greyscale_tokens.dart';
import '../core/utils/figma_scale.dart';

/// Waiting for content to arrive.
///
/// A word, not a rotating glyph. Supporting tone and supporting size: it is
/// something to read while you wait, not something to tap, and the app has no
/// Material spinners left anywhere (see DESIGN.md — no icons).
///
/// For an ACTION that is mid-write, don't use this: the action stays where it
/// is and its own label changes ("Creating account…"), so nothing moves.
class SondrLoading extends StatelessWidget {
  const SondrLoading({super.key, this.label = 'Loading…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    return Center(
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontSize: 13 * scale,
              color: tokens.textSecondary,
            ),
      ),
    );
  }
}

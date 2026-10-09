import 'package:flutter/material.dart';

import '../../../core/theme/greyscale_tokens.dart';
import '../../../core/theme/spacing.dart';
import '../../../core/utils/figma_scale.dart';

/// The "Shared" corner tag on a gallery photo — drop it straight into a tile's
/// [Stack] and it places itself.
///
/// A word, not a glyph, and greyscale like everything else: 12/bold, the
/// metadata tier of the type scale. It carries a dark shadow because it is type
/// sitting over an arbitrary photograph rather than over the app's background —
/// the same thing the calendar does with a day number over its photo fill, and
/// the reason it can be the bright tone without washing out.
///
/// Bottom-left, so it never meets the collage editor's × in the opposite
/// corner, and so a row of tiles reads its tags along one line.
class SharedTag extends StatelessWidget {
  const SharedTag({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    return Positioned(
      left: kSpacingPair * scale,
      bottom: kSpacingPair * scale,
      child: Text(
        'Shared',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 12 * scale,
          fontWeight: FontWeight.w700,
          color: tokens.textPrimary,
          shadows: const [Shadow(color: Color(0xCC000000), blurRadius: 3)],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/theme/greyscale_tokens.dart';
import '../core/theme/spacing.dart';
import '../core/utils/figma_scale.dart';

/// A screen heading with a minimal back affordance, in place of Material's
/// [AppBar].
///
/// The AppBar brought its own title size (~22, off the type table), its own
/// height, a tint on scroll and a platform-standard chevron. This is a section
/// heading (20 / bold) with a plain chevron above it — the same two things the
/// AppBar was doing, at the app's own weight and spacing.
class SondrHeader extends StatelessWidget {
  const SondrHeader({super.key, required this.title, this.onBack});

  final String title;

  /// Defaults to popping the route. Pass null only where there is nothing to
  /// go back to.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final canPop = Navigator.of(context).canPop();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canPop || onBack != null)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
            // Padding, not a bare glyph — the tap target has to clear 44.
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 10 * scale),
              child: Icon(
                Icons.chevron_left,
                size: 28 * scale,
                color: tokens.textPrimary,
              ),
            ),
          ),
        SizedBox(height: kSpacingBase * scale),
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontSize: 20 * scale,
            fontWeight: FontWeight.w700,
            color: tokens.textPrimary,
          ),
        ),
      ],
    );
  }
}

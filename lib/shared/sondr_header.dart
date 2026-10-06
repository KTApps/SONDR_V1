import 'package:flutter/material.dart';

import '../core/theme/greyscale_tokens.dart';
import '../core/utils/figma_scale.dart';

/// A screen heading, in place of Material's [AppBar].
///
/// The AppBar brought its own title size (~22, off the type table), its own
/// height, a tint on scroll and a platform-standard chevron. This is the
/// section heading (20 / bold) and nothing else.
///
/// It carries NO back affordance. A chevron was the last Material icon left
/// in navigation, in an app whose rule is text for every action; going back
/// is a grey "Back" action in the screen's own action group, the way Friends
/// does it. Screens that need one add it themselves — the header does not,
/// because where that action belongs depends on the screen's layout.
class SondrHeader extends StatelessWidget {
  const SondrHeader({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
        fontSize: 20 * scale,
        fontWeight: FontWeight.w700,
        color: tokens.textPrimary,
      ),
    );
  }
}

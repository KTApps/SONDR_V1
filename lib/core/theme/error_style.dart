import 'package:flutter/material.dart';

import '../utils/figma_scale.dart';
import 'greyscale_tokens.dart';

/// The one way a failure is written: supporting SIZE, emphasis TONE.
///
/// 13 / w700 / [GreyscaleTokens.textPrimary]. Colour is not available to mark
/// an error in a greyscale app, so weight and tone carry it — at 13/regular/
/// secondary a failure was byte-identical to a passive hint and read as a
/// footnote. Defined once because it had already drifted between two screens
/// before anyone noticed.
TextStyle? kErrorStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontSize: 13 * figmaScale(context),
          fontWeight: FontWeight.w700,
          color: GreyscaleTokens.of(context).textPrimary,
        );

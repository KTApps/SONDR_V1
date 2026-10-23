import 'package:flutter/material.dart';

import '../core/theme/greyscale_tokens.dart';
import '../core/utils/figma_scale.dart';

/// A quiet inline line: "we have it", not "it failed".
///
/// The counterpart to [SondrError], and deliberately a step below it —
/// 13 / regular / [GreyscaleTokens.textSecondary] against the error style's
/// 13 / w700 / white. A thank-you written in the error style reads as
/// something having gone wrong, which is the opposite of what it says.
///
/// Defined once because three surfaces now say the same thank-you: a
/// reported post, a reported comment and a reported person.
class SondrNotice extends StatelessWidget {
  const SondrNotice(this.message, {super.key, this.textAlign});

  final String message;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) => Text(
    message,
    textAlign: textAlign,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontSize: 13 * figmaScale(context),
      fontWeight: FontWeight.w400,
      color: GreyscaleTokens.of(context).textSecondary,
    ),
  );
}

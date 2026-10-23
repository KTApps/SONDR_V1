import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/greyscale_tokens.dart';
import '../../core/utils/figma_scale.dart';
import '../../shared/legal.dart';

/// One tappable word inside a sentence, or standing on its own.
///
/// A [WidgetSpan] rather than a span with a recogniser: the words have to be
/// findable and tappable as words, both for the person and for the test, and
/// a recogniser's lifetime is one more thing to get wrong.
class LegalWord extends ConsumerWidget {
  const LegalWord({
    super.key,
    required this.label,
    required this.url,
    required this.style,
  });

  final String label;
  final String url;
  final TextStyle style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => ref.read(legalPagesProvider).open(url),
      child: Text(label, style: style),
    );
  }
}

/// What creating an account agrees to.
///
/// Required by the App Store wherever an account is created, and this screen
/// is the only place one is — both of its buttons lead to a sign-up. It sits
/// UNDER the buttons so that adding it moved nothing: every element above it
/// is where it was, and the sentence is the last thing on the page.
///
/// The sentence is one tone (tertiary) with the two linked phrases one step
/// brighter. No underline and no colour: the brighter grey is what says
/// "tappable" everywhere else in the app.
class TermsNotice extends StatelessWidget {
  const TermsNotice({super.key});

  /// The sentence, in one place, so the test can pin the words.
  static const String lead = 'By creating an account, you agree to the ';
  static const String joiner = ' and ';
  static const String terms = 'terms';
  static const String privacy = 'privacy policy';

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final base = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 12 * scale,
      fontWeight: FontWeight.w400,
      color: tokens.textTertiary,
    );
    final link = base.copyWith(color: tokens.textSecondary);

    WidgetSpan word(String label, String url) => WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: LegalWord(label: label, url: url, style: link),
    );

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: lead),
          word(terms, kTermsUrl),
          const TextSpan(text: joiner),
          word(privacy, kPrivacyUrl),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

/// Support, Privacy and Terms, beside Sign out.
///
/// The App Store wants all three reachable from inside the app, and the
/// account block is where everything else about the account already lives.
/// Plain words at the supporting grey, separated by space alone — the same
/// treatment as every other pair of text actions (see DESIGN.md).
class SupportLinks extends StatelessWidget {
  const SupportLinks({super.key});

  /// Reference-canvas gap between the words, and the tap padding each one
  /// carries. Public so the fit test can state the arithmetic it checks.
  static const double gap = 12;
  static const double fontSize = 13;

  static const List<(String, String)> links = [
    ('Support', kSupportUrl),
    ('Privacy', kPrivacyUrl),
    ('Terms', kTermsUrl),
  ];

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    final style = theme.textTheme.bodyMedium!.copyWith(
      fontSize: fontSize * scale,
      fontWeight: FontWeight.w400,
      color: tokens.textSecondary,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (label, url) in links) ...[
          if (label != links.first.$1) SizedBox(width: gap * scale),
          // The vertical padding is the tap target, as it is in SondrAction:
          // a 13pt word is 16 tall, and nobody can hit that reliably.
          Padding(
            padding: EdgeInsets.symmetric(vertical: 12 * scale),
            child: LegalWord(label: label, url: url, style: style),
          ),
        ],
      ],
    );
  }
}

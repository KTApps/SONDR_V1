import 'package:flutter/gestures.dart';
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
/// ONE paragraph, one run of type: the two linked phrases differ from the
/// sentence in colour and nothing else. They used to be [WidgetSpan]s, and a
/// WidgetSpan's child is scaled by the text scale factor BY THE FRAMEWORK
/// (`WidgetSpan.extractFromInlineSpan`) while the `Text` inside it applies
/// the same MediaQuery scale again — so the words rendered at 12 x scale^2.
/// Invisible at the default size and wrong at every other: 18% small at
/// 0.824, 24% large at 1.235. Tap recognisers on plain spans cannot drift
/// from the sentence, because they ARE the sentence.
///
/// No underline and no colour: the brighter grey is what says "tappable"
/// everywhere else in the app.
class TermsNotice extends ConsumerStatefulWidget {
  const TermsNotice({super.key});

  /// The sentence, in one place, so the test can pin the words.
  static const String lead = 'By creating an account, you agree to the ';
  static const String joiner = ' and ';
  static const String terms = 'terms';
  static const String privacy = 'privacy policy';

  @override
  ConsumerState<TermsNotice> createState() => _TermsNoticeState();
}

class _TermsNoticeState extends ConsumerState<TermsNotice> {
  late final TapGestureRecognizer _terms;
  late final TapGestureRecognizer _privacy;

  @override
  void initState() {
    super.initState();
    _terms = TapGestureRecognizer()
      ..onTap = () => ref.read(legalPagesProvider).open(kTermsUrl);
    _privacy = TapGestureRecognizer()
      ..onTap = () => ref.read(legalPagesProvider).open(kPrivacyUrl);
  }

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

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
    // The ONLY difference. Everything else — size, weight, line height, the
    // family, and the one text scaling the paragraph applies — is shared,
    // because these are spans of the same paragraph.
    final link = base.copyWith(color: tokens.textSecondary);

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: TermsNotice.lead),
          TextSpan(
            text: TermsNotice.terms,
            style: link,
            recognizer: _terms,
          ),
          const TextSpan(text: TermsNotice.joiner),
          TextSpan(
            text: TermsNotice.privacy,
            style: link,
            recognizer: _privacy,
          ),
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

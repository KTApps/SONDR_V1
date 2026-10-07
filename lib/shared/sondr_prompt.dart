import 'package:flutter/material.dart';

import '../core/theme/greyscale_tokens.dart';
import '../core/theme/spacing.dart';
import '../core/utils/figma_scale.dart';
import 'sondr_action.dart';
import 'sondr_field.dart';

/// Asks for one short piece of text, in the app's own language.
///
/// Replaces `AlertDialog`, which brought Material's title size, elevation,
/// shadow, button bar and insets — none of which are ours. This is a Sondr
/// surface with a heading, an invisible field and two text actions.
///
/// Returns what was typed, or null if the prompt was dismissed or cancelled.
/// Whitespace-only input returns null, so callers need not re-check.
Future<String?> showSondrPrompt(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
}) async {
  final controller = TextEditingController();
  try {
    final typed = await showDialog<String>(
      context: context,
      builder: (context) {
        final tokens = GreyscaleTokens.of(context);
        final theme = Theme.of(context);
        final scale = figmaScale(context);

        void submit() => Navigator.of(context).pop(controller.text);

        return Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: kSpacingSection * scale),
            // Material only for the ink/text-selection machinery a TextField
            // needs — elevation 0 and our own surface, so it casts nothing
            // and tints nothing.
            child: Material(
              color: tokens.surface,
              elevation: 0,
              borderRadius: BorderRadius.circular(20 * scale),
              child: Padding(
                padding: EdgeInsets.all(kSpacingSection * scale),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // The action size, not Material's dialog title — the
                    // same 15/bold as "View your progress" and every other
                    // heading of this weight.
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 15 * scale,
                        fontWeight: FontWeight.w700,
                        color: tokens.textPrimary,
                      ),
                    ),
                    SizedBox(height: kSpacingBase * scale),
                    // Invisible until typed in: no capsule, no hint. The
                    // heading above already says what it takes, exactly as
                    // on Add Friends and the comments composer.
                    SondrField(
                      controller: controller,
                      filled: false,
                      centered: true,
                      autofocus: true,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => submit(),
                    ),
                    SizedBox(height: kSpacingBase * scale),
                    // Primary first, exit second — the order Delete/Close and
                    // keep/retake use. Not SondrActionPair: these two are not
                    // equals, so Cancel takes the supporting tone.
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SondrAction(label: confirmLabel, onPressed: submit),
                        SizedBox(width: SondrActionPair.gap * scale),
                        SondrAction(
                          label: cancelLabel,
                          supporting: true,
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    final trimmed = typed?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  } finally {
    controller.dispose();
  }
}

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

        // Hovers DIRECTLY above the keyboard rather than sitting centred.
        // The field autofocuses, so the keyboard is always up by the time
        // this is read; centred, it left the Add/Cancel row underneath it.
        // Bottom-aligned and lifted by the inset the whole prompt stays
        // visible, and AnimatedPadding rides the keyboard up rather than
        // snapping once it has arrived.
        return AnimatedPadding(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom:
                MediaQuery.viewInsetsOf(context).bottom +
                kSpacingSection * scale,
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: kSpacingSection * scale,
              ),
              // Material only for the ink/text-selection machinery a TextField
              // needs — elevation 0 and our own surface, so it casts nothing
              // and tints nothing.
              child: Material(
                color: tokens.surface,
                elevation: 0,
                borderRadius: BorderRadius.circular(20 * scale),
                child: Padding(
                  // Section inset on three sides; the BOTTOM is a base unit
                  // because the action row already contributes 12 of its own
                  // tap padding inside this box. 12 + 12 = the 24 at the top,
                  // so the visible inset is square. EdgeInsets.all(24) read
                  // as 36 underneath.
                  padding: EdgeInsets.fromLTRB(
                    kSpacingSection * scale,
                    kSpacingSection * scale,
                    kSpacingSection * scale,
                    kSpacingBase * scale,
                  ),
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
                      // The air above the field. Its partner below is ZERO,
                      // because the action row brings 12 of its own tap
                      // padding — so what you SEE is kSpacingBase either side.
                      // Declaring 12 on both made the lower gap 24.
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
                      // Deliberately no SizedBox: SondrAction's own 12 of
                      // padding is the matching half of the gap above.
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

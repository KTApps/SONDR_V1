import 'package:flutter/material.dart';

import '../core/theme/greyscale_tokens.dart';
import '../features/profile/profile_metrics.dart' show kProfileHairline;
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
  bool obscure = false,
}) async {
  final typed = await showDialog<String>(
    context: context,
    builder: (context) => _TextPrompt(
      title: title,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      obscure: obscure,
    ),
  );
  final trimmed = typed?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}

/// The card [showSondrPrompt] shows.
///
/// A widget of its own so the field's controller lives exactly as long as
/// the route does. Disposing it when `showDialog` RETURNS is too early: the
/// route is popped but still animating out, and the dialog rebuilds once
/// more on the way — "A TextEditingController was used after being
/// disposed", on a prompt that had already closed.
class _TextPrompt extends StatefulWidget {
  const _TextPrompt({
    required this.title,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.obscure,
  });

  final String title;
  final String confirmLabel;
  final String cancelLabel;
  final bool obscure;

  @override
  State<_TextPrompt> createState() => _TextPromptState();
}

class _TextPromptState extends State<_TextPrompt> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = figmaScale(context);

    void submit() => Navigator.of(context).pop(_controller.text);

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
            MediaQuery.viewInsetsOf(context).bottom + kSpacingSection * scale,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: kSpacingSection * scale),
          child: _PromptCard(
            children: [
              _PromptTitle(widget.title),
              // The air above the field. Its partner below is ZERO,
              // because the action row brings 12 of its own tap
              // padding — so what you SEE is kSpacingBase either side.
              // Declaring 12 on both made the lower gap 24.
              SizedBox(height: kSpacingBase * scale),
              // Invisible until typed in: no capsule, no hint. The
              // heading above already says what it takes, exactly as
              // on Add Friends and the comments composer.
              //
              // [obscure] is for a password — the one thing this is ever
              // asked for that must not be shown, autocorrected or
              // capitalised.
              SondrField(
                controller: _controller,
                filled: false,
                centered: true,
                autofocus: true,
                obscureText: widget.obscure,
                autocorrect: !widget.obscure,
                textCapitalization: widget.obscure
                    ? TextCapitalization.none
                    : TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => submit(),
              ),
              // Deliberately no SizedBox: SondrAction's own 12 of
              // padding is the matching half of the gap above.
              _PromptActions(
                confirmLabel: widget.confirmLabel,
                cancelLabel: widget.cancelLabel,
                onConfirm: submit,
                onCancel: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Asks a yes/no question, in the app's own language.
///
/// Shares a surface with the prompt above — the same card, the same
/// heading, the same pair of actions. What differs is what sits between
/// them: a field there, a sentence here. And this one is centred, because
/// there is no keyboard for it to sit above.
///
/// Returns true only when the primary action is tapped. Cancelling, or
/// dismissing it by tapping outside, is a no.
Future<bool> showSondrConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
}) async {
  final said = await showDialog<bool>(
    context: context,
    builder: (context) {
      final tokens = GreyscaleTokens.of(context);
      final theme = Theme.of(context);
      final scale = figmaScale(context);

      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: kSpacingSection * scale),
          child: _PromptCard(
            children: [
              _PromptTitle(title),
              SizedBox(height: kSpacingBase * scale),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 13 * scale,
                  color: tokens.textSecondary,
                ),
              ),
              // No SizedBox: the action row's own 12 of tap padding is the
              // other half of the gap above it.
              _PromptActions(
                confirmLabel: confirmLabel,
                cancelLabel: cancelLabel,
                onConfirm: () => Navigator.of(context).pop(true),
                onCancel: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      );
    },
  );
  return said ?? false;
}

/// The card both prompts are drawn on.
///
/// Material only for the ink and text-selection machinery a TextField
/// needs — elevation 0 and our own surface, so it casts nothing and tints
/// nothing.
/// A list of choices in the confirm's own card: a title, an optional
/// line, then one action per choice with Cancel beneath them.
///
/// The same card, the same title, the same centred position as
/// [showSondrConfirm] — it is the same question with more than two
/// answers. Returns the chosen value, or null for Cancel and for a tap
/// outside.
///
/// Every choice takes the page's full tone: none of them is the safe one.
/// Cancel is the exit and takes the supporting tone, as it does
/// everywhere else.
Future<T?> showSondrChoice<T>(
  BuildContext context, {
  String? title,
  String? body,
  required List<({String label, T value})> choices,
  String cancelLabel = 'Cancel',
  Set<T> quiet = const {},
  T? ruleAbove,
}) {
  return showDialog<T>(
    context: context,
    builder: (context) {
      final tokens = GreyscaleTokens.of(context);
      final theme = Theme.of(context);
      final scale = figmaScale(context);

      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: kSpacingSection * scale),
          child: _PromptCard(
            // With nothing above them, the actions' own 12 of tap padding
            // is half the inset, exactly as it is at the bottom — so the
            // card's declared top comes down to 12 and the visible space
            // stays the square 24 the titled card has.
            tightTop: title == null && body == null,
            children: [
              if (title != null) _PromptTitle(title),
              if (body != null) ...[
                if (title != null) SizedBox(height: kSpacingBase * scale),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13 * scale,
                    color: tokens.textSecondary,
                  ),
                ),
              ],
              if (title != null || body != null)
                SizedBox(height: kSpacingBase * scale),
              for (final choice in choices) ...[
                // One line between two groups of choices, the same rule the
                // Profile parts its sections with. No declared gap either
                // side: the actions above and below each bring 12 of their
                // own tap padding, which is the 12/12 every other break on
                // that page uses.
                if (ruleAbove != null && choice.value == ruleAbove)
                  const SizedBox(
                    height: 1,
                    child: ColoredBox(color: kProfileHairline),
                  ),
                SondrAction(
                  label: choice.label,
                  // A choice that acts on the account rather than opening a
                  // page: the supporting tone, but the full weight, so it
                  // reads as an equal answer rather than a cancel.
                  supporting: quiet.contains(choice.value),
                  weight: FontWeight.w700,
                  onPressed: () => Navigator.of(context).pop(choice.value),
                ),
              ],
              SondrAction(
                label: cancelLabel,
                supporting: true,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.children, this.tightTop = false});

  final List<Widget> children;

  /// True when the first child is an action rather than a heading, so the
  /// declared top inset drops to a base unit — the action's own 12 of tap
  /// padding makes up the rest.
  final bool tightTop;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final scale = figmaScale(context);
    return Material(
      color: tokens.surface,
      elevation: 0,
      borderRadius: BorderRadius.circular(20 * scale),
      child: Padding(
        // Section inset on three sides; the BOTTOM is a base unit because
        // the action row already contributes 12 of its own tap padding
        // inside this box. 12 + 12 = the 24 at the top, so the visible
        // inset is square. EdgeInsets.all(24) read as 36 underneath.
        padding: EdgeInsets.fromLTRB(
          kSpacingSection * scale,
          (tightTop ? kSpacingBase : kSpacingSection) * scale,
          kSpacingSection * scale,
          kSpacingBase * scale,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// The action size, not Material's dialog title — the same 15/bold as
/// "View your progress" and every other heading of this weight.
class _PromptTitle extends StatelessWidget {
  const _PromptTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);
    return Text(
      text,
      textAlign: TextAlign.center,
      style: theme.textTheme.titleLarge?.copyWith(
        fontSize: 15 * scale,
        fontWeight: FontWeight.w700,
        color: tokens.textPrimary,
      ),
    );
  }
}

/// Primary first, exit second — the order Delete/Close and keep/retake
/// use. Not SondrActionPair: these two are not equals, so the second takes
/// the supporting tone.
class _PromptActions extends StatelessWidget {
  const _PromptActions({
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    required this.onCancel,
  });

  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scale = figmaScale(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SondrAction(label: confirmLabel, onPressed: onConfirm),
        SizedBox(width: SondrActionPair.gap * scale),
        SondrAction(label: cancelLabel, supporting: true, onPressed: onCancel),
      ],
    );
  }
}

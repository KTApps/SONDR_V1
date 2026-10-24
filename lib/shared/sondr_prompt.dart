import 'dart:async';

import 'package:flutter/material.dart';

import '../core/theme/greyscale_tokens.dart';
import '../core/theme/spacing.dart';
import '../core/utils/figma_scale.dart';
import 'blur_sheet.dart';
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

/// Asks a yes/no question, over a blurred app.
///
/// The same frosted view the Habits page is: the question on Home's title
/// line, the consequence in one quiet line under it, the answer where a
/// habit name would be, and the way out where "Add habit" is. It replaced
/// a centred card — a card is a surface, and a question is not.
///
/// Returns true only when the answer is tapped. Cancelling, tapping the
/// blur, or swiping down is a no.
Future<bool> showSondrConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  String cancelLabel = 'Cancel',
  BlurSheetHandle? within,
}) async {
  BlurView view(BlurSheetHandle handle, void Function(bool) answer) =>
      BlurView(
        title: title,
        explanation: body,
        items: [BlurItem(label: confirmLabel, onTap: () => answer(true))],
        cancelLabel: cancelLabel,
      );

  // Asked inside a sheet that is already open: cross-fade to it rather
  // than open a second one over the first.
  if (within != null) return _askWithin(within, view);

  var said = false;
  await showBlurSheet(
    context,
    (handle) => view(handle, (yes) {
      said = yes;
      handle.close();
    }),
  );
  return said;
}

/// Asks for a password over the blur, with the field where the answers
/// would be.
///
/// The one question in the app that needs typing and still belongs on
/// this surface: it is the middle of a flow that started on it, and
/// dropping to a card halfway through would read as two apps. The field
/// keeps its ordinary style; the blur lifts by whatever the keyboard
/// covers of the exit, and by nothing when there is no keyboard.
///
/// Returns what was typed, or null if it was dismissed. Whitespace-only
/// returns null, so callers need not re-check.
Future<String?> showBlurPassword(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  BlurSheetHandle? within,
}) async {
  final answered = Completer<String?>();
  // The text, as typed. Held here rather than in a controller this
  // function owns: a controller disposed when the function returns is
  // still being rebuilt by the closing animation — the bug the prompt
  // card had, and the reason its field lives in a widget of its own.
  var typed = '';

  void answer() {
    if (!answered.isCompleted) {
      final trimmed = typed.trim();
      answered.complete(trimmed.isEmpty ? null : trimmed);
    }
  }

  BlurView view(BlurSheetHandle handle) => BlurView(
    title: title,
    body: _BlurPasswordField(
      onChanged: (value) => typed = value,
      onSubmitted: () {
        answer();
        if (within == null) handle.close();
      },
    ),
    items: [
      BlurItem(
        label: confirmLabel,
        quiet: true,
        onTap: () {
          answer();
          if (within == null) handle.close();
        },
      ),
    ],
  );

  if (within != null) {
    within.show(view(within));
    within.closed.then((_) {
      if (!answered.isCompleted) answered.complete(null);
    });
    return answered.future;
  }
  await showBlurSheet(context, view);
  if (!answered.isCompleted) answered.complete(null);
  return answered.future;
}

/// The field itself, owning its controller for exactly as long as it is
/// on screen.
class _BlurPasswordField extends StatefulWidget {
  const _BlurPasswordField({required this.onChanged, required this.onSubmitted});

  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;

  @override
  State<_BlurPasswordField> createState() => _BlurPasswordFieldState();
}

class _BlurPasswordFieldState extends State<_BlurPasswordField> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SondrField(
    controller: _controller,
    filled: false,
    centered: true,
    autofocus: true,
    obscureText: true,
    autocorrect: false,
    textCapitalization: TextCapitalization.none,
    textInputAction: TextInputAction.done,
    onChanged: widget.onChanged,
    onSubmitted: (_) => widget.onSubmitted(),
  );
}

/// Show [view] in an open sheet and wait for its answer, or for the sheet
/// to go without one.
///
/// A view shown inside an open sheet does NOT close it when answered: the
/// flow that asked may have another view to cross-fade to, and only the
/// flow knows when it is finished. Cancelling still closes, because
/// Cancel is the sheet's own exit.
Future<bool> _askWithin(
  BlurSheetHandle handle,
  BlurView Function(BlurSheetHandle, void Function(bool)) view,
) {
  final answered = Completer<bool>();
  handle.show(view(handle, (yes) {
    if (!answered.isCompleted) answered.complete(yes);
  }));
  handle.closed.then((_) {
    if (!answered.isCompleted) answered.complete(false);
  });
  return answered.future;
}

/// A list of answers in the same frosted view.
///
/// The same question with more than two answers, so the same surface:
/// each answer is a habit name, Cancel is "Add habit". Returns the chosen
/// value, or null for Cancel and for a tap on the blur.
///
/// [quiet] names the values that take the not-done grey — the ones that
/// act on the account rather than moving around it.
Future<T?> showSondrChoice<T>(
  BuildContext context, {
  String? title,
  String? body,
  required List<({String label, T value})> choices,
  String cancelLabel = 'Cancel',
  Set<T> quiet = const {},
  BlurSheetHandle? within,
}) async {
  BlurView view(void Function(T) answer) => BlurView(
    title: title,
    explanation: body,
    items: [
      for (final choice in choices)
        BlurItem(
          label: choice.label,
          quiet: quiet.contains(choice.value),
          onTap: () => answer(choice.value),
        ),
    ],
    cancelLabel: cancelLabel,
  );

  if (within != null) {
    final answered = Completer<T?>();
    within.show(view((value) {
      if (!answered.isCompleted) answered.complete(value);
    }));
    within.closed.then((_) {
      if (!answered.isCompleted) answered.complete(null);
    });
    return answered.future;
  }

  T? picked;
  await showBlurSheet(
    context,
    (handle) => view((value) {
      picked = value;
      handle.close();
    }),
  );
  return picked;
}

class _PromptCard extends StatelessWidget {
  const _PromptCard({required this.children});

  final List<Widget> children;

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
          kSpacingSection * scale,
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

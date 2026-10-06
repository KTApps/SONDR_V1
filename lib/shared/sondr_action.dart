import 'package:flutter/material.dart';

import '../core/theme/greyscale_tokens.dart';
import '../core/utils/figma_scale.dart';

/// Sondr's one text action.
///
/// Every tappable label in the app uses this — Start, Stop, Enable, Not now —
/// so the controls read as a single system. Plain text in the standard action
/// style (15 / bold / [GreyscaleTokens.textPrimary]): no glyph, no border, no
/// fill, no tracking, no uppercase, no bespoke weight. Actions are uniform and
/// hierarchy comes from position, never from weight or tone (see DESIGN.md).
///
/// Built from a [GestureDetector] rather than a Material button so the app owns
/// its own component. The padding is the tap target — the text alone would be
/// too small a hit area.
class SondrAction extends StatelessWidget {
  const SondrAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.supporting = false,
    this.weight,
  });

  final String label;
  final VoidCallback? onPressed;

  /// An exit or low-priority action — Sign out, and later Remove / Block /
  /// Delete. Grey and regular weight so it sits below the primary actions,
  /// which stay white and bold. Same size and the same tap target: only the
  /// tone and the weight change (see DESIGN.md).
  final bool supporting;

  /// Overrides the action's weight. Used where an action has to match the
  /// text it sits beside — a swipe tray's Remove reads as part of the row,
  /// and Post stays bold while greying out.
  final FontWeight? weight;

  /// An action with no [onPressed] is inert, and has to look it.
  ///
  /// Tone carries it, as everywhere else: [GreyscaleTokens.textTertiary],
  /// a step below even the supporting grey. The WEIGHT is deliberately left
  /// alone so the label keeps its metrics — a disabled action must not
  /// change size and shift whatever sits under it.
  ///
  /// [supporting] OUTRANKS this. An action that is already declared quiet
  /// says what it needs to at the supporting grey, and dimming it a second
  /// time for being unavailable only makes it hard to read — the comments
  /// composer's Post, grey until there is something to send, is the case
  /// this exists for.
  bool get _disabled => onPressed == null;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 20 * scale,
          vertical: 12 * scale,
        ),
        child: Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 15 * scale,
            fontWeight:
                weight ?? (supporting ? FontWeight.w400 : FontWeight.w700),
            color: supporting
                ? tokens.textSecondary
                : (_disabled ? tokens.textTertiary : tokens.textPrimary),
          ),
        ),
      ),
    );
  }
}

/// Two [SondrAction]s side by side, separated by space alone.
///
/// Used wherever a control offers a choice — "Focus / Start" when a session
/// begins, "Pause / Stop" while one runs, and the same treatment anywhere else
/// a pair of text actions sit together. Nothing is drawn between them: the gap
/// is wide enough that the two labels read as separate buttons rather than one
/// phrase, which is the job a divider would otherwise do.
///
/// The spacing is symmetrical whatever the labels are — each action's own
/// padding either side of a shared central gap.
class SondrActionPair extends StatelessWidget {
  const SondrActionPair({
    super.key,
    required this.firstLabel,
    required this.onFirst,
    required this.secondLabel,
    required this.onSecond,
  });

  final String firstLabel;
  final VoidCallback? onFirst;
  final String secondLabel;
  final VoidCallback? onSecond;

  /// Extra space between the pair, over and above each action's own padding.
  static const double _gap = 16;

  @override
  Widget build(BuildContext context) {
    final scale = figmaScale(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SondrAction(label: firstLabel, onPressed: onFirst),
        // On top of each action's own 20 of padding, so the labels sit 56
        // apart — enough to read as two buttons with nothing drawn between.
        SizedBox(width: _gap * scale),
        SondrAction(label: secondLabel, onPressed: onSecond),
      ],
    );
  }
}

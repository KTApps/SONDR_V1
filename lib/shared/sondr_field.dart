import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/greyscale_tokens.dart';
import '../core/theme/spacing.dart';
import '../core/utils/figma_scale.dart';

/// Sondr's text field.
///
/// Material's stock field — an underline that changes weight on focus and a
/// label that floats and shrinks — is the loudest platform tell in the app. A
/// Sondr field is a quiet `surface`-toned capsule with its label sitting still
/// above it: no underline, no float, no animation, nothing that moves when you
/// tap it.
///
/// The label is a body-tier label (15 / bold); the text you type matches it, so
/// the field reads as one thing rather than a label in one voice and an input
/// in another. Greyscale throughout, and the whole field scales with
/// [figmaScale].
class SondrField extends StatelessWidget {
  const SondrField({
    super.key,
    this.label,
    required this.controller,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.onChanged,
    this.autocorrect = true,
    this.inputFormatters,
    this.prefix,
    this.filled = true,
    this.centered = false,
    this.focusNode,
  });

  /// Omit where the surrounding screen already says what the field is for.
  final String? label;
  final TextEditingController controller;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autocorrect;
  final List<TextInputFormatter>? inputFormatters;

  /// Fixed text before the entry point, e.g. the handle's "@".
  final String? prefix;

  /// Whether the capsule is drawn. Unfilled, the field is invisible until
  /// typed in — for a screen where the heading already says what it takes.
  final bool filled;

  /// Centres the text and the cursor.
  final bool centered;

  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    final scale = figmaScale(context);

    final entryStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 15 * scale,
      fontWeight: FontWeight.w700,
      color: tokens.textPrimary,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 15 * scale,
              fontWeight: FontWeight.w700,
              color: tokens.textSecondary,
            ),
          ),
          SizedBox(height: kSpacingPair * scale),
        ],
        Container(
          // Unfilled there is no capsule to pad, so the field contributes no
          // space of its own and the screen's rhythm is the only thing
          // setting the gaps around it.
          padding: EdgeInsets.symmetric(
            horizontal: filled ? 16 * scale : 0,
            vertical: filled ? 14 * scale : 0,
          ),
          decoration: BoxDecoration(
            color: filled ? tokens.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(16 * scale),
          ),
          child: Row(
            mainAxisAlignment:
                centered ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              if (prefix != null) ...[
                Text(
                  prefix!,
                  style: entryStyle?.copyWith(color: tokens.textTertiary),
                ),
              ],
              Flexible(
                fit: centered ? FlexFit.loose : FlexFit.tight,
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: enabled,
                  obscureText: obscureText,
                  keyboardType: keyboardType,
                  textInputAction: textInputAction,
                  onSubmitted: onSubmitted,
                  onChanged: onChanged,
                  autocorrect: autocorrect,
                  inputFormatters: inputFormatters,
                  style: entryStyle,
                  textAlign: centered ? TextAlign.center : TextAlign.start,
                  cursorColor: tokens.textPrimary,
                  cursorWidth: 1.5 * scale,
                  // The capsule IS the field; strip Material's own chrome.
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

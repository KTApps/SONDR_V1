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
    required this.label,
    required this.controller,
    this.enabled = true,
    this.obscureText = false,
    this.keyboardType,
    this.textInputAction,
    this.onSubmitted,
    this.autocorrect = true,
    this.inputFormatters,
    this.prefix,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final bool autocorrect;
  final List<TextInputFormatter>? inputFormatters;

  /// Fixed text before the entry point, e.g. the handle's "@".
  final String? prefix;

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
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 15 * scale,
            fontWeight: FontWeight.w700,
            color: tokens.textSecondary,
          ),
        ),
        SizedBox(height: kSpacingPair * scale),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: 16 * scale,
            vertical: 14 * scale,
          ),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(16 * scale),
          ),
          child: Row(
            children: [
              if (prefix != null) ...[
                Text(
                  prefix!,
                  style: entryStyle?.copyWith(color: tokens.textTertiary),
                ),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  enabled: enabled,
                  obscureText: obscureText,
                  keyboardType: keyboardType,
                  textInputAction: textInputAction,
                  onSubmitted: onSubmitted,
                  autocorrect: autocorrect,
                  inputFormatters: inputFormatters,
                  style: entryStyle,
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

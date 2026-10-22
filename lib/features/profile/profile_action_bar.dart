import 'package:flutter/material.dart';

import '../../core/theme/greyscale_tokens.dart';

/// The actions a profile of somebody else offers, in a bar built exactly
/// like the app's tab bar.
///
/// Same height, same background, same label size, weight and colour, and
/// the three slots sit on the tab bar's own three label centres — so the
/// thumb that reaches for Profile finds Back. Everything the tab bar does
/// to say "this one is selected" is left out: there is no selection here,
/// so no white, no bold and no underline. The underline's SPACE is kept,
/// because it is what puts the labels on the tab bar's line.
///
/// Remove and Block ask before they act ([showSondrConfirm] at the call
/// site). They sit where muscle memory expects a tab, and a tab that acted
/// on the first tap would be a trap.
class ProfileActionBar extends StatelessWidget {
  const ProfileActionBar({
    super.key,
    required this.slots,
  });

  /// Three slots, left to right. A null slot is empty space — the bar keeps
  /// its shape whatever state the profile is in, so Back never moves.
  final List<ProfileBarSlot?> slots;

  /// The bar's own height, above the bottom inset. The tab bar's.
  static const double height = 40;

  /// The label, and the gap and rule beneath it that place the label.
  static const double labelSize = 13;
  static const double underlineGap = 4;
  static const double underlineHeight = 2;

  @override
  Widget build(BuildContext context) {
    final tokens = GreyscaleTokens.of(context);
    final theme = Theme.of(context);
    assert(slots.length == 3, 'the bar stands on the tab bar\'s three slots');

    return Material(
      color: tokens.background,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              for (final slot in slots)
                Expanded(
                  child: slot == null
                      ? const SizedBox.shrink()
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: slot.onTap,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                slot.label,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontSize: labelSize,
                                  fontWeight: FontWeight.w500,
                                  color: tokens.textTertiary,
                                ),
                              ),
                              const SizedBox(height: underlineGap),
                              // The tab bar's underline, unpainted: nothing
                              // here is selected, but the labels still have
                              // to land on its line.
                              const SizedBox(
                                height: underlineHeight,
                                width: 16,
                              ),
                            ],
                          ),
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One slot's label and what it does.
class ProfileBarSlot {
  const ProfileBarSlot({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;
}

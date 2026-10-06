import 'package:flutter/material.dart';

import '../core/theme/error_style.dart';

/// An inline failure message, in place of a Material SnackBar.
///
/// A SnackBar is a floating Material surface with its own colour, elevation
/// and timeout — it belongs to a design system this app does not use, and it
/// takes the failure away from the thing that failed. This sits where the
/// action is, in the app's own error style, and stays until the user changes
/// something.
class SondrError extends StatelessWidget {
  const SondrError(this.message, {super.key, this.textAlign});

  final String message;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) =>
      Text(message, textAlign: textAlign, style: kErrorStyle(context));
}
